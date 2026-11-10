"""A full look at a shared inbox, against an in-memory Pod.

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

# The fake server holds what a Community Solid Server would after Alice turned
# on People in PhotoPod: her face inbox, encrypted with its folder key and
# shared with the Analyser, holding a few photos. Bob has a Pod but has shared
# nothing. The face engine is a stand-in, so the suite runs without the models;
# test_engine.py covers the real one.

from __future__ import annotations

import base64
import json
import unittest
from pathlib import Path

from face_analyser import MODEL_ID, crypto, pod_paths as paths, turtle
from face_analyser.config import (
    AnalyserConfig,
    Config,
    InboxConfig,
    WatchConfig,
)
from face_analyser.engine import EngineConfig, ImageError
from face_analyser.inbox import REQUEST_FORMAT, RESULT_SUFFIX
from face_analyser.keys import PodKeys
from face_analyser.service import RESULT_FORMAT, FaceService, NotShared

from tests.fake_pod import FakePod, FakeSolidClient, encrypted_resource

SERVER = 'https://server'
ANALYSER_WEB_ID = f'{SERVER}/Analyser/profile/card#me'
ALICE = f'{SERVER}/alice/profile/card#me'
BOB = f'{SERVER}/bob/profile/card#me'
APP = 'photopod'
INBOX_PATH = f'{APP}/data/.faces-inbox/'


class FakeEngine:
    """One face per picture, its embedding the picture's own bytes."""

    def __init__(self):
        self.seen: list[bytes] = []

    def analyse(self, data: bytes) -> dict:
        self.seen.append(data)
        if data == b'not a picture':
            raise ImageError('The upload is not a picture OpenCV can read.')
        return {'model': MODEL_ID, 'width': 100, 'height': 80, 'faces': [{
            'box': [0.1, 0.2, 0.3, 0.4], 'score': 0.95,
            'embedding': base64.b64encode(data).decode(),
            'image': None}]}


class PipelineTest(unittest.TestCase):
    def setUp(self):
        self.analyser = FakePod(ANALYSER_WEB_ID, 'analyser-key')
        self.client = FakeSolidClient()
        for pod in (self.analyser, FakePod(ALICE), FakePod(BOB)):
            self._seed_keys(pod)

        self.inbox = paths.data_url(ALICE, APP, '.faces-inbox') + '/'
        self.folder_key = crypto.random_key()
        self._share_with_analyser(self.inbox, self.folder_key)

        self.config = Config(
            analyser=AnalyserConfig(web_id=ANALYSER_WEB_ID, app_dir_name=APP,
                                    server_url=SERVER,
                                    security_key='analyser-key',
                                    client_id='id', client_secret='secret'),
            inbox=InboxConfig(),
            watch=WatchConfig(),
            engine=EngineConfig(models_dir=Path('.')),
        )
        self.engine = FakeEngine()
        self.service = FaceService(self.config, self.client,
                                   PodKeys(self.client, self.config),
                                   self.engine)

    # -- Seeding -----------------------------------------------------------

    def _seed_keys(self, pod: FakePod) -> None:
        iv = crypto.random_iv()
        enc_url = paths.enc_key_url(pod.web_id, APP)
        self.client.resources[enc_url] = (
            f'@prefix solidTerms: <{paths.APPS_TERMS}> .\n'
            f'<{enc_url}>\n'
            f'    solidTerms:encKey "{pod.verification}";\n'
            f'    solidTerms:iv "{base64.b64encode(iv).decode()}";\n'
            f'    solidTerms:salt "{base64.b64encode(pod.salt).decode()}";\n'
            f'    solidTerms:keyVersion "2";\n'
            f'    solidTerms:prvKey '
            f'"{crypto.aes_cbc_encrypt(pod.private_pem, pod.master_key, iv)}".\n'
        )
        shared_url = paths.shared_key_url(pod.web_id, APP)
        self.client.resources[shared_url] = (
            f'@prefix solidTerms: <{paths.APPS_TERMS}> .\n'
            f'<{shared_url}> a solidTerms:SharedKeys .\n')

    def _share_with_analyser(self, resource_url: str, key: bytes) -> None:
        """What solidpod's `grantPermission()` leaves in the recipient's Pod."""

        shared_url = paths.shared_key_url(ANALYSER_WEB_ID, APP)
        public = self.analyser.public_key
        entry = turtle.shared_keys_document(
            shared_url,
            crypto.unique_resource_id(resource_url, ANALYSER_WEB_ID),
            crypto.rsa_encrypt(public, resource_url),
            crypto.rsa_encrypt(public, 'read,write'),
            crypto.rsa_encrypt(public, base64.b64encode(key).decode()),
        )
        graph = turtle.parse(self.client.resources[shared_url])
        graph.parse(data=entry, format='turtle')
        self.client.resources[shared_url] = graph.serialize(format='turtle')

    def leave(self, key: str, image: bytes) -> str:
        """Leave a photo in Alice's inbox, as PhotoPod does."""

        url = f'{self.inbox}{key}.enc.ttl'
        self.client.resources[url] = encrypted_resource(
            url,
            {'format': REQUEST_FORMAT, 'version': 1,
             'image': base64.b64encode(image).decode()},
            self.folder_key,
            inherit_from=INBOX_PATH,
        )
        return url

    def answer(self, key: str) -> dict:
        """Open the answer for [key] as PhotoPod's readPod() does: by the
        folder its inheritKeyFrom names, with Alice's own folder key."""

        url = f'{self.inbox}{key}{RESULT_SUFFIX}'
        fields = turtle.triple_map(self.client.resources[url], base=url)[url]
        self.assertEqual(
            turtle.single(fields[paths.APPS_TERMS + 'inheritKeyFrom']),
            INBOX_PATH)
        self.assertEqual(turtle.single(fields[paths.APPS_TERMS + 'path']),
                         f'{INBOX_PATH}{key}{RESULT_SUFFIX}')
        return json.loads(crypto.aes_ctr_decrypt(
            turtle.single(fields[paths.APPS_TERMS + 'encData']),
            self.folder_key,
            base64.b64decode(turtle.single(fields[paths.APPS_TERMS + 'iv']))))

    # -- Looks -------------------------------------------------------------

    def test_answers_each_photo_in_the_users_own_inbox(self):
        a = self.leave('a' * 32, b'photo a')
        b = self.leave('b' * 32, b'photo b')

        reports = self.service.sweep()

        self.assertEqual([(r.web_id, r.analysed, r.failed, r.pending)
                          for r in reports], [(ALICE, 2, 0, 0)])
        answer = self.answer('a' * 32)
        self.assertEqual(answer['format'], RESULT_FORMAT)
        self.assertEqual(answer['model'], MODEL_ID)
        self.assertEqual(base64.b64decode(answer['faces'][0]['embedding']),
                         b'photo a')

        # The photos leave the inbox once their answers are written.
        self.assertNotIn(a, self.client.resources)
        self.assertNotIn(b, self.client.resources)
        self.assertEqual(self.engine.seen, [b'photo a', b'photo b'])

        # Nothing about Alice is written into the Analyser's own Pod.
        analyser_root = paths.pod_root(ANALYSER_WEB_ID)
        written = [url for url, _ in self.client.patched]
        written += [u for u in self.client.resources if u.startswith(analyser_root)
                    and 'faces' in u]
        self.assertEqual(written, [])

    def test_an_answer_is_not_mistaken_for_a_photo(self):
        self.leave('a' * 32, b'photo a')
        self.service.sweep()
        self.assertEqual(self.service.sweep(), [])
        self.assertEqual(self.engine.seen, [b'photo a'])

    def test_a_picture_that_cannot_be_read_is_answered_and_removed(self):
        bad = self.leave('c' * 32, b'not a picture')
        report = self.service.run(ALICE)
        self.assertEqual(report.failed, 1)
        self.assertIn('failed', self.answer('c' * 32))
        self.assertNotIn(bad, self.client.resources)

    def test_a_pod_that_shared_nothing_is_refused(self):
        with self.assertRaises(NotShared):
            self.service.run(BOB)

    def test_an_inbox_closed_to_the_analyser_is_passed_over(self):
        self.leave('a' * 32, b'photo a')
        self.client.private_urls.add(self.inbox)
        self.assertEqual(self.service.sweep(), [])

    def test_a_large_inbox_is_worked_through_in_batches(self):
        self.config.inbox.max_per_run = 2
        for letter in 'abcde':
            self.leave(letter * 32, f'photo {letter}'.encode())
        self.assertEqual(self.service.run(ALICE).pending, 3)
        self.assertEqual(self.service.run(ALICE).pending, 1)
        self.assertEqual(self.service.run(ALICE).pending, 0)
        self.assertEqual(len(self.engine.seen), 5)

    def test_results_left_by_the_earlier_version_are_deleted(self):
        old = paths.data_url(ANALYSER_WEB_ID, APP,
                             'faces/server-alice/faces-results.json.enc.ttl')
        self.client.resources[old] = 'encrypted faces'
        self.client.resources[old + '.acl'] = 'acl'
        self.assertEqual(self.service.forget_old_results(), 1)
        self.assertNotIn(old, self.client.resources)
        self.assertNotIn(old + '.acl', self.client.resources)
        self.assertEqual(self.service.forget_old_results(), 0)

    def test_the_shared_keys_are_opened_once_while_unchanged(self):
        from unittest import mock

        self.service.keys.shared_resources()
        with mock.patch('face_analyser.keys.crypto.rsa_decrypt') as decrypt:
            self.service.keys.shared_resources()
        decrypt.assert_not_called()

if __name__ == '__main__':
    unittest.main()
