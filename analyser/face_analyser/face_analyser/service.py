"""Answering the requests users make by sharing their face inboxes.

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

# The service has no interface of its own: no port, nothing an app calls. It
# talks only to the Solid server it sits beside, as the Analyser, and acts only
# when asked.
#
# A user asks by choosing photos in PhotoPod and tapping Identify People:
# PhotoPod leaves those photos in the user's face inbox and then shares the
# inbox with the Analyser. Sharing writes into the Analyser's own shared-keys
# file, and the server tells the service so at once (notify.py). The service
# then reads that file, and for each inbox newly shared with it, and only
# those, takes every photo waiting there (`<key>.enc.ttl`) and
#
#   1. reads and decrypts it with the inbox's folder key, in memory;
#   2. finds the faces in it;
#   3. writes what it found into the same inbox, as `<key>.faces.enc.ttl`,
#      encrypted with the same folder key, so the answer lands in the user's
#      own Pod and only the user (and the Analyser) can read it;
#   4. only then removes the photo.
#
# Once every photo is answered it writes `done` in the inbox. PhotoPod files
# the answers, ends the share and removes the inbox. Nothing about any user is
# kept by the Analyser, in its Pod or on this host.

from __future__ import annotations

import base64
import json
import logging
import time
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from . import MODEL_ID, crypto, inbox, notify, pod_paths as paths, turtle
from .config import Config
from .engine import FaceEngine, ImageError
from .keys import PodKeys, SharedResource
from .solid_client import ForbiddenError, NotFoundError, SolidClient, SolidError

log = logging.getLogger(__name__)

RESULT_FORMAT = 'photopod-face-result'


class NotShared(Exception):
    """Raised when a Pod has not shared its face inbox with the Analyser."""


@dataclass
class InboxReport:
    """What answering one request did."""

    web_id: str
    analysed: int = 0
    failed: int = 0
    errors: list[str] = field(default_factory=list)

    def to_json(self) -> dict[str, Any]:
        return {'web_id': self.web_id, 'analysed': self.analysed,
                'failed': self.failed, 'errors': self.errors}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec='milliseconds')


class FaceService:
    """Answers each face inbox shared with the Analyser, once per share."""

    def __init__(self, config: Config, client: SolidClient, keys: PodKeys,
                 engine: FaceEngine):
        self.config = config
        self.client = client
        self.keys = keys
        self.engine = engine

        # The shares already answered, each by its sealed key. Each sharing
        # seals the key afresh, so a user asking again is a new share even
        # when the same inbox is shared, and a share that has gone is
        # forgotten, keeping this no larger than the shared-keys file.

        self._answered: set[str] = set()

    # -- Requests ------------------------------------------------------------

    def respond(self) -> list[InboxReport]:
        """Answer every inbox shared with the Analyser since the last time."""

        shared = inbox.shared_inboxes(self.keys.shared_resources(), self.config)
        reports = []
        for url, share in sorted(shared.items()):
            if share.sealed_key in self._answered:
                continue
            try:
                report = self._look(url, share)
            except (ForbiddenError, NotFoundError) as e:
                # Shared once and since removed, but left in the shared-keys
                # file: there is nothing to answer.
                log.debug('%s: %s', url, e)
            except SolidError as e:
                # Tried again on the next change, or the next start.
                log.warning('%s: %s', url, e)
                continue
            else:
                reports.append(report)
            self._answered.add(share.sealed_key)
        self._answered &= {share.sealed_key for share in shared.values()}
        return reports

    def run(self, web_id: str) -> InboxReport:
        """Answer the inbox of [web_id]'s Pod now, asked for or not."""

        url = inbox.inbox_url(web_id, self.config)
        share = inbox.shared_inboxes(
            self.keys.shared_resources(), self.config).get(url)
        if share is None:
            raise NotShared(f'{url} has not been shared with the Analyser')
        return self._look(url, share)

    def watch(self, listen: Callable[[str], Iterable[str]] = notify.messages
              ) -> None:
        """Answer each request as it is made, until stopped.

        The server is asked to say whenever the shared-keys file changes,
        which is what a user's request does to it. Requests made while the
        service was not listening are answered as soon as it is.
        """

        topic = paths.shared_key_url(self.config.analyser.web_id,
                                     self.config.analyser.app_dir_name)
        pause = max(1.0, self.config.watch.reconnect_seconds)
        while True:
            try:
                receive_from = notify.subscribe(
                    self.client, self.config.analyser.pod_root, topic)
                log.info('Listening for requests to %s',
                         self.config.analyser.web_id)
                self.respond()
                for _ in listen(receive_from):
                    self.respond()
                log.info('The server closed the notification channel')
            except Exception:  # noqa: BLE001 - listen again shortly
                log.exception('Listening for requests failed')
            time.sleep(pause)

    # -- One request ---------------------------------------------------------

    def _look(self, url: str, share: SharedResource) -> InboxReport:
        owner = paths.web_id_of(
            paths.owner_pod_root(url, self.config.analyser.app_dir_name))
        report = InboxReport(web_id=owner)
        keys = {url: share.key}

        for item in inbox.items_in(self.client.list_container(url)):
            try:
                answer = self._analyse(item, keys)
            except NotFoundError:
                continue
            except (SolidError, crypto.DecryptionError) as e:
                # A photo that cannot be opened with the key shared is left
                # where it is, unanswered: the key, not the photo, is wrong.
                report.errors.append(f'{item.key}: {e}')
                log.warning('cannot read %s: %s', item.url, e)
                continue

            try:
                self._answer(url, item, share.key, answer)
                self.client.delete(item.url)
            except SolidError as e:
                report.errors.append(f'{item.key}: {e}')
                log.warning('cannot answer %s: %s', item.url, e)
                continue
            if 'failed' in answer:
                report.failed += 1
            else:
                report.analysed += 1

        self.client.put_text(f'{url}{inbox.DONE_NAME}', 'done\n',
                             content_type='text/plain')
        log.info('%s: %d analysed, %d failed%s',
                 paths.pod_slug(owner), report.analysed, report.failed,
                 f', {len(report.errors)} error(s)' if report.errors else '')
        return report

    def _analyse(self, item: inbox.InboxItem,
                 keys: dict[str, bytes]) -> dict[str, Any]:
        """The answer for one photo: its faces, or why it could not be read.
        A photo that cannot be read would fail the same way again, so it is
        answered rather than left in the inbox."""

        answer: dict[str, Any] = {'format': RESULT_FORMAT, 'version': 1,
                                  'model': MODEL_ID, 'analysed': _now()}
        text = self.client.get_text(item.url)
        try:
            image = inbox.decode_request(
                inbox.decrypt_document(text, item.url, keys, self.config))
            found = self.engine.analyse(image)
            del image
        except crypto.DecryptionError:
            raise
        except (inbox.RequestError, ImageError, ValueError) as e:
            log.info('%s: %s', item.url, e)
            answer['failed'] = str(e)
            return answer
        answer.update(width=found['width'], height=found['height'],
                      faces=found['faces'])
        return answer

    def _answer(self, inbox_url: str, item: inbox.InboxItem, key: bytes,
                answer: dict[str, Any]) -> None:
        """Write [answer] beside the photo, encrypted with the inbox's key, in
        the form solidpod's `writePod(inheritKeyFrom:)` writes, so that
        PhotoPod reads it with `readPod()` like any file of its own."""

        url = f'{inbox_url}{item.key}{inbox.RESULT_SUFFIX}'
        owner = paths.web_id_of(
            paths.owner_pod_root(inbox_url, self.config.analyser.app_dir_name))
        iv = crypto.random_iv()
        self.client.put_text(url, turtle.encrypted_document(
            file_url=url,
            resource_path=paths.resource_path_in_pod(url, owner),
            iv_b64=base64.b64encode(iv).decode('ascii'),
            enc_data_b64=crypto.aes_ctr_encrypt(
                json.dumps(answer, separators=(',', ':')), key, iv),
            inherit_key_from=paths.resource_path_in_pod(inbox_url, owner),
        ))
