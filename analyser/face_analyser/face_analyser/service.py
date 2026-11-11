"""Watching the shared inboxes, and answering into them.

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
# inboxes users have shared with it: a face inbox for People, a tag inbox for
# Tags, each shared or not as the user chose. It lists each inbox, and for
# every photo waiting there (`<key>.enc.ttl`) it
#
#   1. reads and decrypts it with the inbox's folder key, in memory;
#   2. finds the faces in it, or the tags for it, as the inbox asks;
#   3. writes what it found into the same inbox, as `<key>.faces.enc.ttl` or
#      `<key>.tags.enc.ttl`, encrypted with the same folder key, so the answer
#      lands in the user's own Pod and only the user (and the Analyser) can
#      read it;
#   4. only then removes the photo.
#
# PhotoPod files each answer in the user's faces or tags file and deletes it.
# Nothing about any user is kept by the Analyser, in its Pod or on this host.

from __future__ import annotations

import base64
import json
import logging
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Protocol

from . import crypto, inbox, pod_paths as paths, turtle
from .config import Config
from .engine import ImageError
from .keys import PodKeys, SharedResource
from .solid_client import ForbiddenError, NotFoundError, SolidClient, SolidError

log = logging.getLogger(__name__)

RESULT_FORMAT = 'photopod-face-result'
TAG_RESULT_FORMAT = 'photopod-tag-result'


class NotShared(Exception):
    """Raised when a Pod has not shared an inbox with the Analyser."""


class Engine(Protocol):
    @property
    def model_id(self) -> str: ...

    def analyse(self, data: bytes) -> dict[str, Any]: ...


@dataclass(frozen=True)
class InboxKind:
    """One kind of inbox: what is asked in it, and how it is answered."""

    name: str
    folder: str
    request_format: str
    result_format: str
    result_suffix: str
    engine: Engine

    # What the engine's answer carries over into the result, beside its
    # model and the picture's size.

    fields: tuple[str, ...]

    @property
    def fragment(self) -> str:
        """What the URL of an inbox of this kind ends with."""

        return f'/{paths.DATA_DIR}/{self.folder.strip("/")}/'


@dataclass
class InboxReport:
    """What one look at one inbox did."""

    web_id: str
    kind: str = 'faces'
    analysed: int = 0
    failed: int = 0
    pending: int = 0
    errors: list[str] = field(default_factory=list)

    def to_json(self) -> dict[str, Any]:
        return {'web_id': self.web_id, 'kind': self.kind,
                'analysed': self.analysed,
                'failed': self.failed, 'pending': self.pending,
                'errors': self.errors}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec='milliseconds')


class AnalyserService:
    """Looks at the shared inboxes and answers into them."""

    def __init__(self, config: Config, client: SolidClient, keys: PodKeys,
                 engine: Engine, tagger: Engine | None = None):
        self.config = config
        self.client = client
        self.keys = keys
        self.kinds = [InboxKind(
            name='faces', folder=config.inbox.folder,
            request_format=inbox.REQUEST_FORMAT, result_format=RESULT_FORMAT,
            result_suffix=inbox.RESULT_SUFFIX, engine=engine,
            fields=('faces',))]
        if tagger is not None and config.tags is not None:
            self.kinds.append(InboxKind(
                name='tags', folder=config.tags.folder,
                request_format=inbox.TAG_REQUEST_FORMAT,
                result_format=TAG_RESULT_FORMAT,
                result_suffix=inbox.TAG_RESULT_SUFFIX, engine=tagger,
                fields=('tags',)))

    def kind(self, name: str) -> InboxKind | None:
        return next((k for k in self.kinds if k.name == name), None)

    # -- Looking -----------------------------------------------------------

    def sweep(self) -> list[InboxReport]:
        """One look at every shared inbox, reporting those that held photos."""

        shared = self.keys.shared_resources()
        reports = []
        for kind in self.kinds:
            for url, share in sorted(inbox.shared_inboxes(
                    shared, self.config, kind.fragment).items()):
                report = self._try_look(kind, url, share)
                if report is not None:
                    reports.append(report)
        return reports

    def _try_look(self, kind: InboxKind, url: str,
                  share: SharedResource) -> InboxReport | None:
        try:
            report = self._look(kind, url, share)
        except (ForbiddenError, NotFoundError) as e:
            # Shared once, since unshared or removed: the entry stays in the
            # shared-keys file, but there is nothing to do.
            log.debug('%s: %s', url, e)
            return None
        except SolidError as e:
            log.warning('%s: %s', url, e)
            return None
        if report.analysed or report.failed or report.errors:
            return report
        return None

    def run(self, web_id: str, kind: str = 'faces') -> InboxReport:
        """One look at the [kind] inbox of [web_id]'s Pod."""

        found = self.kind(kind)
        if found is None:
            raise NotShared(f'{kind} are not looked for by this Analyser')
        url = inbox.inbox_url(web_id, self.config, found.folder)
        share = inbox.shared_inboxes(
            self.keys.shared_resources(), self.config, found.fragment).get(url)
        if share is None:
            raise NotShared(f'{url} has not been shared with the Analyser')
        return self._look(found, url, share)

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
        log.info('Watching the inboxes (%s) shared with %s every %.0f s',
                 ', '.join(k.name for k in self.kinds),
                 self.config.analyser.web_id, interval)
        while True:
            started = time.monotonic()
            try:
                self.sweep()
            except Exception:  # noqa: BLE001 - the next look tries again
                log.exception('Looking at the inboxes failed')
            time.sleep(max(0.0, interval - (time.monotonic() - started)))

    # -- One inbox -----------------------------------------------------------

    def _look(self, kind: InboxKind, url: str,
              share: SharedResource) -> InboxReport:
        owner = paths.web_id_of(
            paths.owner_pod_root(url, self.config.analyser.app_dir_name))
        report = InboxReport(web_id=owner, kind=kind.name)

        requests = inbox.items_in(self.client.list_container(url))
        batch = requests[: max(1, self.config.inbox.max_per_run)]
        report.pending = len(requests) - len(batch)
        keys = {url: share.key}

        for item in batch:
            try:
                answer = self._analyse(kind, item, keys)
            except NotFoundError:
                continue
            except SolidError as e:
                report.errors.append(f'{item.key}: {e}')
                log.warning('cannot read %s: %s', item.url, e)
                continue

            try:
                self._answer(kind, url, item, share.key, answer)
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
            log.info('%s %s: %d analysed, %d failed, %d pending%s',
                     paths.pod_slug(owner), kind.name, report.analysed, report.failed,
                     report.pending,
                     f', {len(report.errors)} error(s)' if report.errors else '')
        return report

    def _analyse(self, kind: InboxKind, item: inbox.InboxItem,
                 keys: dict[str, bytes]) -> dict[str, Any]:
        """The answer for one photo: what was found in it, or why it could
        not be read. A photo that cannot be read would fail the same way
        again, so it is answered rather than left in the inbox."""

        answer: dict[str, Any] = {'format': kind.result_format, 'version': 1,
                                  'model': kind.engine.model_id,
                                  'analysed': _now()}
        text = self.client.get_text(item.url)
        try:
            image = inbox.decode_request(
                inbox.decrypt_document(text, item.url, keys, self.config),
                kind.request_format)
            found = kind.engine.analyse(image)
            del image
        except (inbox.RequestError, crypto.DecryptionError, ImageError,
                ValueError) as e:
            log.info('%s: %s', item.url, e)
            answer['failed'] = str(e)
            return answer
        answer.update(model=found.get('model', answer['model']),
                      width=found['width'], height=found['height'])
        answer.update({name: found[name] for name in kind.fields})
        return answer

    def _answer(self, kind: InboxKind, inbox_url: str, item: inbox.InboxItem,
                key: bytes, answer: dict[str, Any]) -> None:
        """Write [answer] beside the photo, encrypted with the inbox's key, in
        the form solidpod's `writePod(inheritKeyFrom:)` writes, so that
        PhotoPod reads it with `readPod()` like any file of its own."""

        url = f'{inbox_url}{item.key}{kind.result_suffix}'
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
