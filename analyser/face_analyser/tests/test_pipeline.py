"""A full run against an in-memory Pod: inbox in, results shared back.

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
import http.client
import json
import threading
import unittest
from pathlib import Path

from face_analyser import MODEL_ID, crypto, pod_paths as paths, turtle
from face_analyser.auth import AuthConfig, Authenticator
from face_analyser.config import (
    AnalyserConfig,
    Config,
    InboxConfig,
    ServiceConfig,
    SharingConfig,
)
from face_analyser.engine import EngineConfig, ImageError
from face_analyser.inbox import REQUEST_FORMAT
from face_analyser.keys import PodKeys
from face_analyser.service import FaceService, NotShared

from tests.fake_pod import FakePod, FakeSolidClient, encrypted_resource

SERVER = 'https://server'
ANALYSER_WEB_ID = f'{SERVER}/Analyser/profile/card#me'
ALICE = f'{SERVER}/alice/profile/card#me'
BOB = f'{SERVER}/bob/profile/card#me'
APP = 'photopod'
INBOX_PATH = f'{APP}/data/.faces-inbox/'


class FakeEngine:
    """One face per picture, its score taken from the picture's bytes."""

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
        self.alice = FakePod(ALICE, 'alice-key')
        self.bob = FakePod(BOB, 'bob-key')
        self.client = FakeSolidClient()
        for pod in (self.analyser, self.alice, self.bob):
            self._seed_keys(pod)
        ind_url = paths.ind_key_url(ANALYSER_WEB_ID, APP)
        self.client.resources[ind_url] = turtle.individual_keys_document(
            ind_url, {})

        self.inbox = paths.data_url(ALICE, APP, '.faces-inbox') + '/'
        self.folder_key = crypto.random_key()
        self._share_with_analyser(self.inbox, self.folder_key)

        self.config = Config(
            analyser=AnalyserConfig(web_id=ANALYSER_WEB_ID, app_dir_name=APP,
                                    server_url=SERVER,
                                    security_key='analyser-key',
                                    client_id='id', client_secret='secret'),
            inbox=InboxConfig(),
            sharing=SharingConfig(),
            service=ServiceConfig(port=0, poll_seconds=0),
            auth=AuthConfig(required=False),
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
        pub_url = paths.pub_key_url(pod.web_id, APP)
        self.client.resources[pub_url] = (
            f'@prefix solidTerms: <{paths.APPS_TERMS}> .\n'
            f'<{pub_url}>\n'
            f'    solidTerms:pubKey "{pod.public_body}".\n'
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

    def results_as_alice(self, url: str) -> dict:
        """Open the published results the way PhotoPod's readExternalPod()
        does: with the key the Analyser left in Alice's sharing inbox."""

        shared_url = paths.shared_key_url(ALICE, APP)
        record = turtle.triple_map(
            self.client.resources[shared_url], base=shared_url)[
            paths.APPS_RES_ID + crypto.unique_resource_id(url, ALICE)]
        key = base64.b64decode(crypto.rsa_decrypt(
            self.alice.private_key,
            turtle.single(record[paths.APPS_DATA + 'sharedKey'])))
        fields = turtle.triple_map(self.client.resources[url], base=url)[url]
        return json.loads(crypto.aes_ctr_decrypt(
            turtle.single(fields[paths.APPS_TERMS + 'encData']), key,
            base64.b64decode(turtle.single(fields[paths.APPS_TERMS + 'iv']))))

    def shares_to_alice(self) -> int:
        shared_url = paths.shared_key_url(ALICE, APP)
        return sum(1 for url, _ in self.client.patched if url == shared_url)

    # -- Runs --------------------------------------------------------------

    def test_analyses_the_inbox_and_shares_the_results_back(self):
        a = self.leave('a' * 32, b'photo a')
        b = self.leave('b' * 32, b'photo b')

        report = self.service.run(ALICE)

        self.assertEqual((report.analysed, report.failed, report.pending),
                         (2, 0, 0))
        self.assertEqual(report.result_url,
                         f'{SERVER}/Analyser/{APP}/data/faces/server-alice/'
                         'faces-results.json.enc.ttl')
        results = self.results_as_alice(report.result_url)
        self.assertEqual(results['model'], MODEL_ID)
        self.assertEqual(set(results['items']), {'a' * 32, 'b' * 32})
        face = results['items']['a' * 32]['faces'][0]
        self.assertEqual(base64.b64decode(face['embedding']), b'photo a')

        # The photos leave the inbox once their results are safely out.
        self.assertNotIn(a, self.client.resources)
        self.assertNotIn(b, self.client.resources)
        self.assertEqual(self.engine.seen, [b'photo a', b'photo b'])

    def test_results_are_kept_until_the_app_takes_them(self):
        self.leave('a' * 32, b'photo a')
        url = self.service.run(ALICE).result_url
        self.leave('b' * 32, b'photo b')

        report = self.service.run(ALICE)
        self.assertEqual(report.waiting, 2)
        self.assertEqual(set(self.results_as_alice(url)['items']),
                         {'a' * 32, 'b' * 32})

        report = self.service.run(ALICE, ack=['a' * 32, 'b' * 32])
        self.assertEqual(report.waiting, 0)
        self.assertEqual(self.results_as_alice(url)['items'], {})

    def test_a_picture_that_cannot_be_read_is_reported_and_removed(self):
        bad = self.leave('c' * 32, b'not a picture')
        report = self.service.run(ALICE)
        self.assertEqual(report.failed, 1)
        results = self.results_as_alice(report.result_url)
        self.assertIn('c' * 32, results['failed'])
        self.assertNotIn(bad, self.client.resources)

    def test_a_pod_that_shared_nothing_is_refused(self):
        with self.assertRaises(NotShared):
            self.service.run(BOB)

    def test_a_large_inbox_is_worked_through_in_batches(self):
        self.config.inbox.max_per_run = 2
        for letter in 'abcde':
            self.leave(letter * 32, f'photo {letter}'.encode())
        self.assertEqual(self.service.run(ALICE).pending, 3)
        self.assertEqual(self.service.run(ALICE).pending, 1)
        self.assertEqual(self.service.run(ALICE).pending, 0)
        self.assertEqual(len(self.engine.seen), 5)

    def test_the_key_is_handed_over_once(self):
        self.leave('a' * 32, b'photo a')
        self.service.run(ALICE)
        first = self.shares_to_alice()
        self.leave('b' * 32, b'photo b')
        self.service.run(ALICE)
        self.assertEqual(self.shares_to_alice(), first)

    def test_nothing_new_writes_nothing(self):
        self.leave('a' * 32, b'photo a')
        url = self.service.run(ALICE).result_url
        before = self.client.resources[url]
        self.service.run(ALICE)
        self.assertEqual(self.client.resources[url], before)

    def test_the_sweep_runs_only_for_inboxes_with_photos(self):
        self.assertEqual(self.service.sweep(), [])
        self.leave('a' * 32, b'photo a')
        reports = self.service.sweep()
        self.assertEqual([r.web_id for r in reports], [ALICE])
        self.assertEqual(reports[0].analysed, 1)


class ServerTest(unittest.TestCase):
    """The HTTP interface, with authentication off: test_auth.py covers what
    it checks, and with it off the WebID comes in the body."""

    @classmethod
    def setUpClass(cls):
        from face_analyser.server import FaceServer

        cls.pipeline = PipelineTest('test_nothing_new_writes_nothing')
        cls.pipeline.setUp()
        config = cls.pipeline.config
        cls.server = FaceServer(config, cls.pipeline.service,
                                Authenticator(config.auth))
        cls.port = cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def request(self, method, path, body=None):
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=30)
        payload = None if body is None else json.dumps(body).encode()
        conn.request(method, path, body=payload,
                     headers={'Content-Type': 'application/json'})
        response = conn.getresponse()
        data = json.loads(response.read() or b'{}')
        conn.close()
        return response.status, data

    def test_health(self):
        status, body = self.request('GET', '/v1/health')
        self.assertEqual(status, 200)
        self.assertEqual(body['model'], MODEL_ID)
        self.assertEqual(body['analyser'], ANALYSER_WEB_ID)

    def test_analyse(self):
        self.pipeline.leave('d' * 32, b'photo d')
        status, body = self.request('POST', '/photopod-faces/v1/analyse',
                                    {'web_id': ALICE})
        self.assertEqual(status, 200)
        self.assertEqual(body['analysed'], 1)
        self.assertTrue(body['result_url'].endswith('.enc.ttl'))

    def test_not_shared(self):
        status, body = self.request('POST', '/v1/analyse', {'web_id': BOB})
        self.assertEqual(status, 409)
        self.assertEqual(body['code'], 'not_shared')

    def test_bad_ack(self):
        status, _ = self.request('POST', '/v1/analyse',
                                 {'web_id': ALICE, 'ack': 'everything'})
        self.assertEqual(status, 400)

    def test_no_photo_route(self):
        status, _ = self.request('POST', '/v1/faces', {})
        self.assertEqual(status, 404)


if __name__ == '__main__':
    unittest.main()
