"""Command line for the PhotoPod face analyser.

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

#   python -m face_analyser --config config.yaml watch
#   python -m face_analyser --config config.yaml check
#   python -m face_analyser --config config.yaml run-once [WEBID...]
#   python -m face_analyser --config config.yaml fetch-models
#   python -m face_analyser --config config.yaml analyse PHOTO...
#
# Exit status 2 is a configuration error, which the systemd unit does not
# restart on, since restarting cannot fix it.

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

from . import MODEL_ID, __version__, notify
from .config import Config, ConfigError, load
from .engine import FaceEngine, ImageError
from .inbox import shared_inboxes
from .keys import KeyStoreError, PodKeys
from .models import ModelError, ensure_all
from .service import FaceService, NotShared
from .solid_client import SolidClient, SolidError

log = logging.getLogger('face_analyser')

EXIT_CONFIG = 2


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='face_analyser',
        description='Find the faces in the photos PhotoPod users share with '
                    'the Analyser Pod, and write them back into their Pods.')
    parser.add_argument('--config', type=Path, default=Path('config.yaml'))
    parser.add_argument('--verbose', '-v', action='store_true')
    parser.add_argument('--version', action='version', version=__version__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('watch', help='answer each request as it is made, '
                                      'for ever (systemd\'s mode)')
    commands.add_parser('check', help='verify the models and the Analyser Pod')
    once = commands.add_parser('run-once', help='answer the requests waiting, '
                                                'or the inboxes of the Pods '
                                                'named')
    once.add_argument('web_ids', nargs='*')
    commands.add_parser('fetch-models', help='download the two models')
    analyse = commands.add_parser('analyse', help='the faces in local photos')
    analyse.add_argument('photos', nargs='+', type=Path)
    analyse.add_argument('--full', action='store_true',
                         help='print embeddings and face pictures as well')
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format='%(asctime)s %(levelname)s %(name)s: %(message)s')
    for noisy in ('httpx', 'httpcore', 'rdflib'):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    try:
        config = load(args.config)
    except ConfigError as e:
        print(f'Configuration error: {e}', file=sys.stderr)
        return EXIT_CONFIG
    for warning in config.warnings:
        log.warning(warning)

    if args.command == 'fetch-models':
        try:
            for path in ensure_all(config.engine.models_dir):
                print(f'OK  {path}')
        except ModelError as e:
            print(e, file=sys.stderr)
            return 1
        return 0

    try:
        engine = FaceEngine(config.engine, download=False)
    except ModelError as e:
        print(e, file=sys.stderr)
        return EXIT_CONFIG

    if args.command == 'analyse':
        return _analyse(engine, args.photos, full=args.full)

    try:
        config.require_credentials()
    except ConfigError as e:
        print(f'Configuration error: {e}', file=sys.stderr)
        return EXIT_CONFIG

    client = SolidClient(config.analyser.server_url, config.analyser.client_id,
                         config.analyser.client_secret,
                         timeout=config.analyser.request_timeout)
    try:
        client.login()
        keys = PodKeys(client, config)
        keys.unlock()
    except (SolidError, KeyStoreError) as e:
        print(f'The Analyser Pod cannot be used: {e}', file=sys.stderr)
        return EXIT_CONFIG

    service = FaceService(config, client, keys, engine)
    try:
        if args.command == 'check':
            return _check(config, service)
        if args.command == 'run-once':
            return _run_once(service, args.web_ids)
        try:
            service.watch()
        except KeyboardInterrupt:
            pass
        return 0
    finally:
        client.close()


def _check(config: Config, service: FaceService) -> int:
    print(f'OK    models load ({MODEL_ID})')
    print(f'OK    logged in and unlocked {config.analyser.web_id}')
    try:
        inboxes = shared_inboxes(service.keys.shared_resources(), config)
    except SolidError as e:
        print(f'FAIL  cannot read the shared keys: {e}')
        return 1
    print(f'OK    {len(inboxes)} Pod(s) share a face inbox')
    for url in sorted(inboxes):
        print(f'      {url}')
    try:
        channel = notify.subscription_service(
            service.client, config.analyser.pod_root)
    except SolidError as e:
        print(f'FAIL  the server cannot say when requests are made: {e}')
        return 1
    print(f'OK    requests are notified through {channel}')
    return 0


def _run_once(service: FaceService, web_ids: list[str]) -> int:
    if not web_ids:
        reports = service.respond()
    else:
        reports = []
        for web_id in web_ids:
            try:
                reports.append(service.run(web_id))
            except NotShared as e:
                print(f'{web_id}: {e}', file=sys.stderr)
    json.dump([r.to_json() for r in reports], sys.stdout, indent=2)
    print()
    return 1 if any(r.errors for r in reports) else 0


def _analyse(engine: FaceEngine, photos: list[Path], *, full: bool) -> int:
    status = 0
    results = {}
    for photo in photos:
        try:
            result = engine.analyse(photo.read_bytes())
        except (OSError, ImageError) as e:
            print(f'{photo}: {e}', file=sys.stderr)
            status = 1
            continue
        if not full:
            for face in result['faces']:
                face.pop('embedding')
                face['image'] = bool(face.get('image'))
        results[str(photo)] = result
    json.dump(results, sys.stdout, indent=2)
    print()
    return status


if __name__ == '__main__':
    sys.exit(main())
