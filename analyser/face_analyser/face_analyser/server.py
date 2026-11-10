"""The HTTP interface PhotoPod calls to ask for a run.

Copyright (C) 2026, Software Innovation Institute, ANU.

Licensed under the GNU General Public License, Version 3 (the "License").

License: https://opensource.org/license/gpl-3-0.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program. If not, see https://opensource.org/license/gpl-3-0.

Authors: Tony Chen
"""

# Two routes:
#
#   GET  /v1/health    {"status": "ok", "model": ..., "analyser": <WebID>}
#   POST /v1/analyse   {"ack": [keys]}  ->  what the run did (RunReport)
#
# No photo ever comes this way. The app has already left its photos in its own
# Pod and shared them with the Analyser; this call only says "now", so that
# the app does not wait for the next sweep, and names, through the caller's
# Solid login, the one Pod to look at. The answer says where the results were
# published; the app reads them from there with the key the Analyser shared.

from __future__ import annotations

import json
import logging
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from . import MODEL_ID, __version__
from .auth import Authenticator, AuthError
from .config import Config
from .keys import KeyStoreError
from .service import FaceService, NotShared
from .solid_client import SolidError

log = logging.getLogger(__name__)

ANALYSE_PATH = '/v1/analyse'
HEALTH_PATH = '/v1/health'


class FaceServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, config: Config, service: FaceService,
                 authenticator: Authenticator):
        self.config = config
        self.service = service
        self.authenticator = authenticator
        super().__init__((config.service.host, config.service.port), _Handler)


class _Handler(BaseHTTPRequestHandler):
    server: FaceServer
    server_version = f'PhotoPodFaceAnalyser/{__version__}'
    protocol_version = 'HTTP/1.1'

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        log.debug('%s %s', self.address_string(), format % args)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(HTTPStatus.NO_CONTENT)
        self._cors()
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers',
                         'Authorization, DPoP, Content-Type')
        self.send_header('Access-Control-Max-Age', '600')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        if self._route() in ('/', '/health', HEALTH_PATH):
            self._json(HTTPStatus.OK, {
                'status': 'ok',
                'service': 'photopod-face-analyser',
                'version': __version__,
                'model': MODEL_ID,
                'analyser': self.server.config.analyser.web_id,
                'inbox': self.server.config.inbox.folder,
            })
        else:
            self._error(HTTPStatus.NOT_FOUND, 'No such route.')

    def do_POST(self) -> None:  # noqa: N802
        body = self._body()
        if body is None:
            return
        if self._route() != ANALYSE_PATH:
            self._error(HTTPStatus.NOT_FOUND, 'No such route.')
            return

        try:
            caller = self.server.authenticator.authenticate(
                self.headers, 'POST', self._public_url())
        except AuthError as e:
            log.info('Refused %s: %s', self.address_string(), e)
            self._error(HTTPStatus.UNAUTHORIZED, str(e),
                        extra={'WWW-Authenticate': 'DPoP'})
            return
        if caller is None:
            # Authentication switched off, for development: the WebID is
            # taken on trust from the request.
            web_id = str(body.get('web_id') or '')
            if not web_id:
                self._error(HTTPStatus.BAD_REQUEST, 'web_id is needed.')
                return
        else:
            web_id = caller.web_id

        ack = body.get('ack') or []
        if not isinstance(ack, list) or not all(isinstance(k, str) for k in ack):
            self._error(HTTPStatus.BAD_REQUEST, 'ack must be a list of names.')
            return

        try:
            report = self.server.service.run(web_id, ack)
        except NotShared as e:
            self._json(HTTPStatus.CONFLICT, {'error': str(e),
                                             'code': 'not_shared'})
            return
        except KeyStoreError as e:
            log.error('The Analyser Pod cannot be unlocked: %s', e)
            self._error(HTTPStatus.SERVICE_UNAVAILABLE,
                        'The Analyser is not set up correctly.')
            return
        except SolidError as e:
            log.warning('Run for %s failed: %s', web_id, e)
            self._error(HTTPStatus.BAD_GATEWAY, f'The Solid server said: {e}')
            return
        except Exception:  # noqa: BLE001 - reported, never the data
            log.exception('Run for %s failed', web_id)
            self._error(HTTPStatus.INTERNAL_SERVER_ERROR, 'The run failed.')
            return
        self._json(HTTPStatus.OK, report.to_json())

    # The path without any query, and without the prefix a reverse proxy
    # may leave on it.

    def _route(self) -> str:
        path = self.path.split('?', 1)[0].rstrip('/') or '/'
        for route in (ANALYSE_PATH, HEALTH_PATH):
            if path.endswith(route):
                return route
        return path

    def _public_url(self) -> str:
        public = self.server.config.service.public_url
        if public:
            return public.rstrip('/') + ANALYSE_PATH
        proto = (self.headers.get('X-Forwarded-Proto') or 'http').split(',')[0]
        host = (self.headers.get('X-Forwarded-Host')
                or self.headers.get('Host')
                or f'{self.server.config.service.host}:'
                   f'{self.server.config.service.port}')
        prefix = (self.headers.get('X-Forwarded-Prefix') or '').rstrip('/')
        path = self.path.split('?', 1)[0]
        return f'{proto.strip()}://{host.split(",")[0].strip()}{prefix}{path}'

    # The request body as JSON, or None once an error has been sent.

    def _body(self) -> dict[str, Any] | None:
        try:
            length = int(self.headers.get('Content-Length') or 0)
        except ValueError:
            length = -1
        if length < 0 or length > self.server.config.service.max_body_bytes:
            self.close_connection = True
            self._error(HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                        'The request is too large.')
            return None
        raw = self.rfile.read(length) if length else b''
        if not raw.strip():
            return {}
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            self._error(HTTPStatus.BAD_REQUEST, 'The body must be JSON.')
            return None
        if not isinstance(body, dict):
            self._error(HTTPStatus.BAD_REQUEST, 'The body must be an object.')
            return None
        return body

    def _cors(self) -> None:
        origins = self.server.config.service.cors_origins
        origin = self.headers.get('Origin')
        if '*' in origins:
            self.send_header('Access-Control-Allow-Origin', '*')
        elif origin and origin in origins:
            self.send_header('Access-Control-Allow-Origin', origin)
            self.send_header('Vary', 'Origin')

    def _json(self, status: HTTPStatus, body: dict[str, Any],
              extra: dict[str, str] | None = None) -> None:
        payload = json.dumps(body, separators=(',', ':')).encode('utf-8')
        self.send_response(status)
        self._cors()
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(payload)))
        for name, value in (extra or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(payload)

    def _error(self, status: HTTPStatus, message: str,
               extra: dict[str, str] | None = None) -> None:
        self._json(status, {'error': message}, extra)


def _sweeper(service: FaceService, seconds: int,
             stop: threading.Event) -> None:
    while not stop.wait(seconds):
        try:
            service.sweep()
        except Exception:  # noqa: BLE001 - the next sweep tries again
            log.exception('Sweep failed')


def serve(config: Config, service: FaceService,
          authenticator: Authenticator | None = None) -> None:
    server = FaceServer(config, service,
                        authenticator or Authenticator(config.auth))
    stop = threading.Event()
    if config.service.poll_seconds > 0:
        threading.Thread(target=_sweeper, daemon=True, name='sweeper',
                         args=(service, config.service.poll_seconds, stop)
                         ).start()
    log.info('Listening on http://%s:%d%s for %s (model %s, auth %s, sweep '
             'every %ss)', config.service.host, config.service.port,
             ANALYSE_PATH, config.analyser.web_id, MODEL_ID,
             'Solid-OIDC' if config.auth.required else 'OFF',
             config.service.poll_seconds or 'never')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        server.server_close()
