"""Answering the requests users make by sharing their inboxes.

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
# talks only to Solid servers, as the Analyser, and acts only when asked.
#
# A user asks by choosing photos in PhotoPod and tapping Identify People, or
# Tag Photos: PhotoPod leaves those photos in the user's face inbox, or tag
# inbox, and then shares that inbox with the Analyser. Sharing writes into the
# Analyser's own shared-keys file, and the server tells the service so at once
# (notify.py). The service then reads that file, and for each inbox newly
# shared with it, and only those, takes every photo waiting there
# (`<key>.enc.ttl`) and
#
#   1. reads and decrypts it with the inbox's folder key, in memory;
#   2. finds the faces in it, or the tags for it, as the inbox asks;
#   3. writes what it found into the same inbox, as `<key>.faces.enc.ttl` or
#      `<key>.tags.enc.ttl`, encrypted with the same folder key, so the answer
#      lands in the user's own Pod and only the user (and the Analyser) can
#      read it;
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
from typing import Any, Protocol

from . import crypto, inbox, notify, pod_paths as paths, turtle
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
    """What answering one request did."""

    web_id: str
    kind: str = 'faces'
    analysed: int = 0
    failed: int = 0
    errors: list[str] = field(default_factory=list)

    def to_json(self) -> dict[str, Any]:
        return {'web_id': self.web_id, 'kind': self.kind,
                'analysed': self.analysed, 'failed': self.failed,
                'errors': self.errors}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec='milliseconds')


class AnalyserService:
    """Answers each inbox shared with the Analyser, once per share."""

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

        # The shares already answered, each by its sealed key. Each sharing
        # seals the key afresh, so a user asking again is a new share even
        # when the same inbox is shared, and a share that has gone is
        # forgotten, keeping this no larger than the shared-keys file.

        self._answered: set[str] = set()

    def kind(self, name: str) -> InboxKind | None:
        return next((k for k in self.kinds if k.name == name), None)

    # -- Requests ------------------------------------------------------------

    def respond(self) -> list[InboxReport]:
        """Answer every inbox shared with the Analyser since the last time."""

        shared = self.keys.shared_resources()
        current: set[str] = set()
        reports = []
        for kind in self.kinds:
            inboxes = inbox.shared_inboxes(shared, self.config, kind.fragment)
            current |= {share.sealed_key for share in inboxes.values()}
            for url, share in sorted(inboxes.items()):
                if share.sealed_key in self._answered:
                    continue
                try:
                    report = self._look(kind, url, share)
                except (ForbiddenError, NotFoundError) as e:
                    # Shared once and since removed, but left in the
                    # shared-keys file: there is nothing to answer.
                    log.debug('%s: %s', url, e)
                except SolidError as e:
                    # Tried again on the next change, or the next start.
                    log.warning('%s: %s', url, e)
                    continue
                else:
                    reports.append(report)
                self._answered.add(share.sealed_key)
        self._answered &= current
        return reports

    def run(self, web_id: str, kind: str = 'faces') -> InboxReport:
        """Answer the [kind] inbox of [web_id]'s Pod now, asked for or not."""

        found = self.kind(kind)
        if found is None:
            raise NotShared(f'{kind} are not looked for by this Analyser')
        url = inbox.inbox_url(web_id, self.config, found.folder)
        share = inbox.shared_inboxes(
            self.keys.shared_resources(), self.config, found.fragment).get(url)
        if share is None:
            raise NotShared(f'{url} has not been shared with the Analyser')
        return self._look(found, url, share)

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
                log.info('Listening for requests (%s) to %s',
                         ', '.join(k.name for k in self.kinds),
                         self.config.analyser.web_id)
                self.respond()
                for _ in listen(receive_from):
                    self.respond()
                log.info('The server closed the notification channel')
            except Exception:  # noqa: BLE001 - listen again shortly
                log.exception('Listening for requests failed')
            time.sleep(pause)

    # -- One request ---------------------------------------------------------

    def _look(self, kind: InboxKind, url: str,
              share: SharedResource) -> InboxReport:
        owner = paths.web_id_of(
            paths.owner_pod_root(url, self.config.analyser.app_dir_name))
        report = InboxReport(web_id=owner, kind=kind.name)
        keys = {url: share.key}

        for item in inbox.items_in(self.client.list_container(url)):
            try:
                answer = self._analyse(kind, item, keys)
            except NotFoundError:
                continue
            except (SolidError, crypto.DecryptionError) as e:
                # A photo that cannot be opened with the key shared is left
                # where it is, unanswered: the key, not the photo, is wrong.
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

        self.client.put_text(f'{url}{inbox.DONE_NAME}', 'done\n',
                             content_type='text/plain')
        log.info('%s %s: %d analysed, %d failed%s',
                 paths.pod_slug(owner), kind.name, report.analysed,
                 report.failed,
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
        except crypto.DecryptionError:
            raise
        except (inbox.RequestError, ImageError, ValueError) as e:
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
