"""Watching the shared face inboxes, and answering into them.

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
# talks only to the Solid server it sits beside, as the Analyser, and finds its
# work by looking.
#
# Every few seconds it reads the Analyser's shared-keys file, which lists the
# face inboxes users have shared with it, and lists each inbox. For every photo
# waiting there (`<key>.enc.ttl`) it
#
#   1. reads and decrypts it with the inbox's folder key, in memory;
#   2. finds the faces in it;
#   3. writes what it found into the same inbox, as `<key>.faces.enc.ttl`,
#      encrypted with the same folder key, so the answer lands in the user's
#      own Pod and only the user (and the Analyser) can read it;
#   4. only then removes the photo.
#
# PhotoPod files each answer in the user's faces file and deletes it. Nothing
# about any user is kept by the Analyser, in its Pod or on this host.

from __future__ import annotations

import base64
import json
import logging
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from . import MODEL_ID, crypto, inbox, pod_paths as paths, turtle
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
    """What one look at one inbox did."""

    web_id: str
    analysed: int = 0
    failed: int = 0
    pending: int = 0
    errors: list[str] = field(default_factory=list)

    def to_json(self) -> dict[str, Any]:
        return {'web_id': self.web_id, 'analysed': self.analysed,
                'failed': self.failed, 'pending': self.pending,
                'errors': self.errors}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec='milliseconds')


class FaceService:
    """Looks at the shared face inboxes and answers into them."""

    def __init__(self, config: Config, client: SolidClient, keys: PodKeys,
                 engine: FaceEngine):
        self.config = config
        self.client = client
        self.keys = keys
        self.engine = engine

    # -- Looking -----------------------------------------------------------

    def sweep(self) -> list[InboxReport]:
        """One look at every shared inbox, reporting those that held photos."""

        shared = self.keys.shared_resources()
        reports = []
        for url, share in sorted(inbox.shared_inboxes(shared, self.config).items()):
            try:
                report = self._look(url, share)
            except (ForbiddenError, NotFoundError) as e:
                # Shared once, since unshared or removed: the entry stays in
                # the shared-keys file, but there is nothing to do.
                log.debug('%s: %s', url, e)
                continue
            except SolidError as e:
                log.warning('%s: %s', url, e)
                continue
            if report.analysed or report.failed or report.errors:
                reports.append(report)
        return reports

    def run(self, web_id: str) -> InboxReport:
        """One look at the inbox of [web_id]'s Pod."""

        url = inbox.inbox_url(web_id, self.config)
        share = inbox.shared_inboxes(
            self.keys.shared_resources(), self.config).get(url)
        if share is None:
            raise NotShared(f'{url} has not been shared with the Analyser')
        return self._look(url, share)

    def forget_old_results(self) -> int:
        """Delete what an earlier version of this service published in the
        Analyser Pod, returning how many files went.

        That version kept each Pod's faces in
        `<analyser>/photopod/data/faces/<pod-id>/faces-results.json.enc.ttl`
        and shared them back. This one writes answers into the user's own
        inbox, so nothing about any user belongs in the Analyser Pod.
        """

        root = paths.data_url(self.config.analyser.web_id,
                              self.config.analyser.app_dir_name, 'faces') + '/'
        try:
            folders = self.client.list_container(root)
        except NotFoundError:
            return 0
        removed = 0
        for folder in folders:
            files = self.client.list_container(folder) if folder.endswith('/') else [folder]
            for url in files:
                self.client.delete(f'{url}.acl')
                removed += self.client.delete(url)
            if folder.endswith('/'):
                self.client.delete(folder)
        self.client.delete(root)
        log.info('Deleted %d result file(s) left in the Analyser Pod by an '
                 'earlier version', removed)
        return removed

    def watch(self) -> None:
        """Look at every shared inbox, again and again, until stopped."""

        try:
            self.forget_old_results()
        except SolidError as e:
            log.warning('Could not delete the results an earlier version '
                        'left in the Analyser Pod: %s', e)

        interval = max(1.0, self.config.watch.poll_seconds)
        log.info('Watching the face inboxes shared with %s every %.0f s',
                 self.config.analyser.web_id, interval)
        while True:
            started = time.monotonic()
            try:
                self.sweep()
            except Exception:  # noqa: BLE001 - the next look tries again
                log.exception('Looking at the face inboxes failed')
            time.sleep(max(0.0, interval - (time.monotonic() - started)))

    # -- One inbox -----------------------------------------------------------

    def _look(self, url: str, share: SharedResource) -> InboxReport:
        owner = paths.web_id_of(
            paths.owner_pod_root(url, self.config.analyser.app_dir_name))
        report = InboxReport(web_id=owner)

        requests = inbox.items_in(self.client.list_container(url))
        batch = requests[: max(1, self.config.inbox.max_per_run)]
        report.pending = len(requests) - len(batch)
        keys = {url: share.key}

        for item in batch:
            try:
                answer = self._analyse(item, keys)
            except NotFoundError:
                continue
            except SolidError as e:
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

        if report.analysed or report.failed or report.errors:
            log.info('%s: %d analysed, %d failed, %d pending%s',
                     paths.pod_slug(owner), report.analysed, report.failed,
                     report.pending,
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
        except (inbox.RequestError, crypto.DecryptionError, ImageError,
                ValueError) as e:
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
