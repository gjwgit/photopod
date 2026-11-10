"""One run of the face analyser for one Pod.

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

# A run, for the Pod of one WebID:
#
#   1. find that Pod's face inbox among the resources shared with the Analyser;
#   2. read the results already published for it, and drop whatever the app
#      says it has taken into its own faces file (`ack`);
#   3. read, decrypt and analyse up to `inbox.max_per_run` photos from the
#      inbox, in memory;
#   4. publish the results in the Analyser Pod, encrypted, and share them with
#      that Pod (the same protocol HealthPod's analyser uses);
#   5. only then remove the photos analysed from the inbox, so a run that
#      fails part way loses nothing.
#
# Everything travels between this service and the Solid server it sits beside.
# No photo is written to this host's disk, and once the app has taken its
# results the Analyser Pod keeps nothing of them either.

from __future__ import annotations

import base64
import json
import logging
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from . import MODEL_ID, crypto, inbox, pod_paths as paths, turtle
from .config import Config
from .engine import FaceEngine, ImageError
from .keys import PodKeys
from .publisher import Publisher
from .solid_client import ForbiddenError, NotFoundError, SolidClient, SolidError

log = logging.getLogger(__name__)

RESULTS_FORMAT = 'photopod-face-results'
RESULTS_FILE = 'faces-results.json'


class NotShared(Exception):
    """Raised when the caller's Pod has not shared its face inbox."""


@dataclass
class RunReport:
    """What one run did, as the app is told."""

    web_id: str
    result_url: str | None = None
    generated: str | None = None
    analysed: int = 0
    failed: int = 0
    pending: int = 0
    waiting: int = 0
    errors: list[str] = field(default_factory=list)

    def to_json(self) -> dict[str, Any]:
        return {
            'web_id': self.web_id,
            'model': MODEL_ID,
            'result_url': self.result_url,
            'generated': self.generated,
            'analysed': self.analysed,
            'failed': self.failed,
            'pending': self.pending,
            'waiting': self.waiting,
            'errors': self.errors,
        }


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec='milliseconds')


def empty_results() -> dict[str, Any]:
    return {'format': RESULTS_FORMAT, 'version': 1, 'model': MODEL_ID,
            'generated': None, 'items': {}, 'failed': {}}


class FaceService:
    """Runs analyses, one at a time, against the Solid server."""

    def __init__(self, config: Config, client: SolidClient, keys: PodKeys,
                 engine: FaceEngine, publisher: Publisher | None = None):
        self.config = config
        self.client = client
        self.keys = keys
        self.engine = engine
        self.publisher = publisher or Publisher(client, keys, config)
        self._lock = threading.Lock()

    # -- Addresses ---------------------------------------------------------

    def result_url(self, web_id: str) -> str:
        """Where the results for [web_id]'s Pod are published."""

        suffix = '.enc.ttl' if self.config.sharing.encrypt_results else ''
        return paths.data_url(
            self.config.analyser.web_id, self.config.analyser.app_dir_name,
            self._relative_path(web_id) + suffix)

    def _relative_path(self, web_id: str) -> str:
        return (f'{self.config.sharing.results_dir.strip("/")}/'
                f'{paths.pod_slug(web_id)}/{RESULTS_FILE}')

    # -- Runs --------------------------------------------------------------

    def run(self, web_id: str, ack: list[str] | tuple[str, ...] = ()) -> RunReport:
        """Analyse what [web_id]'s Pod has left in its inbox, after
        forgetting the results named in [ack]."""

        with self._lock:
            return self._run(web_id, set(ack))

    def sweep(self) -> list[RunReport]:
        """A run for every Pod whose inbox holds photos, for apps that left
        photos and closed before asking."""

        reports = []
        with self._lock:
            shared = inbox.shared_inboxes(self.keys.shared_resources(), self.config)
        for url in sorted(shared):
            web_id = paths.web_id_of(
                paths.owner_pod_root(url, self.config.analyser.app_dir_name))
            try:
                if not inbox.items_in(self.client.list_container(url)):
                    continue
                reports.append(self.run(web_id))
            except (SolidError, NotShared) as e:
                log.warning('sweep of %s: %s', url, e)
        return reports

    def _run(self, web_id: str, ack: set[str]) -> RunReport:
        report = RunReport(web_id=web_id)
        url = inbox.inbox_url(web_id, self.config)
        shared = self.keys.shared_resources()
        if url not in inbox.shared_inboxes(shared, self.config):
            raise NotShared(f'{url} has not been shared with the Analyser')
        key_index = {item.resource_url: item.key for item in shared}

        results = self._read_results(web_id)
        changed = False
        for key in ack:
            if results['items'].pop(key, None) is not None:
                changed = True
            if results['failed'].pop(key, None) is not None:
                changed = True

        try:
            members = inbox.items_in(self.client.list_container(url))
        except ForbiddenError as e:
            raise NotShared(f'{url} cannot be listed: {e}') from e
        batch = members[: max(1, self.config.inbox.max_per_run)]
        report.pending = len(members) - len(batch)

        done: list[inbox.InboxItem] = []
        for item in batch:
            try:
                text = self.client.get_text(item.url)
                image = inbox.decode_request(inbox.decrypt_document(
                    text, item.url, key_index, self.config))
                found = self.engine.analyse(image)
                del image
                results['items'][item.key] = {
                    'width': found['width'],
                    'height': found['height'],
                    'faces': found['faces'],
                    'analysed': _now(),
                }
                results['failed'].pop(item.key, None)
                report.analysed += 1
            except NotFoundError:
                continue
            except (inbox.RequestError, crypto.DecryptionError, ImageError,
                    ValueError) as e:
                # Analysing it again would fail the same way, so it is
                # reported and taken out of the inbox like the rest.
                results['failed'][item.key] = str(e)
                results['items'].pop(item.key, None)
                report.failed += 1
                log.info('%s: %s', item.url, e)
            except SolidError as e:
                report.errors.append(f'{item.key}: {e}')
                log.warning('cannot read %s: %s', item.url, e)
                continue
            done.append(item)
            changed = True

        report.waiting = len(results['items']) + len(results['failed'])
        if changed:
            results['generated'] = _now()
            published = self.publisher.publish(
                payload=results,
                relative_path=self._relative_path(web_id),
                recipients=[web_id],
            )
            if web_id in published.failures:
                # Without the key the app cannot read the results, so the
                # photos stay in the inbox to be tried again.
                report.errors.append(published.failures[web_id])
                done = []

        for item in done:
            try:
                self.client.delete(item.url)
            except SolidError as e:
                report.errors.append(f'{item.key}: not removed: {e}')
                log.warning('cannot remove %s: %s', item.url, e)

        report.result_url = self.result_url(web_id)
        report.generated = results['generated']
        log.info('%s: %d analysed, %d failed, %d pending, %d waiting for the '
                 'app', paths.pod_slug(web_id), report.analysed, report.failed,
                 report.pending, report.waiting)
        return report

    def _read_results(self, web_id: str) -> dict[str, Any]:
        """The results published for [web_id] by an earlier run, or empty
        ones. Results from other models are dropped: their embeddings
        cannot be compared with these."""

        url = self.result_url(web_id)
        try:
            text = self.client.get_text_or_none(url)
        except SolidError as e:
            log.warning('cannot read %s, starting afresh: %s', url, e)
            return empty_results()
        if text is None:
            return empty_results()

        try:
            if self.config.sharing.encrypt_results:
                key = self.keys.individual_key(url)
                if key is None:
                    return empty_results()
                record = turtle.triple_map(text, base=url).get(url) or {}
                text = crypto.aes_ctr_decrypt(
                    turtle.single(record.get(paths.APPS_TERMS + 'encData')),
                    key,
                    base64.b64decode(
                        turtle.single(record.get(paths.APPS_TERMS + 'iv'))),
                )
            data = json.loads(text)
        except Exception as e:  # noqa: BLE001 - unreadable means start again
            log.warning('cannot open %s, starting afresh: %s', url, e)
            return empty_results()

        if data.get('format') != RESULTS_FORMAT or data.get('model') != MODEL_ID:
            return empty_results()
        data.setdefault('items', {})
        data.setdefault('failed', {})
        return data
