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

# The fake server holds what a Community Solid Server would after Alice asked
# PhotoPod to identify the people in some photos: her face inbox, encrypted
# with its folder key and shared with the Analyser, holding those photos. Bob
# has a Pod but has asked for nothing. The face engine is a stand-in, so the suite runs without the models;
# test_engine.py covers the real one.

from __future__ import annotations

import base64
import json
import unittest
from pathlib import Path

from face_analyser import MODEL_ID, crypto, notify, pod_paths as paths, turtle
from face_analyser.config import (
    AnalyserConfig,
    Config,
    InboxConfig,
    WatchConfig,
)
from face_analyser.engine import EngineConfig, ImageError
from face_analyser.inbox import (
    REQUEST_FORMAT,
    RESULT_SUFFIX,
    TAG_REQUEST_FORMAT,
    TAG_RESULT_SUFFIX,
)
from face_analyser.keys import PodKeys
from face_analyser.service import (
    RESULT_FORMAT,
    TAG_RESULT_FORMAT,
    AnalyserService,
    NotShared,
)
from face_analyser.tagger import TagConfig

from tests.fake_pod import FakePod, FakeSolidClient, encrypted_resource

SERVER = 'https://server'
ANALYSER_WEB_ID = f'{SERVER}/Analyser/profile/card#me'
ALICE = f'{SERVER}/alice/profile/card#me'
BOB = f'{SERVER}/bob/profile/card#me'
APP = 'photopod'
INBOX_PATH = f'{APP}/data/.faces-inbox/'
TAG_INBOX_PATH = f'{APP}/data/.tags-inbox/'
TAG_MODEL_ID = 'siglip-b16-webli:tags-v1'


class FakeEngine:
    """One face per picture, its embedding the picture's own bytes."""

    model_id = MODEL_ID

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


class FakeTagger:
    """One tag per picture, named after the picture."""

    model_id = TAG_MODEL_ID

    def __init__(self):
        self.seen: list[bytes] = []

    def analyse(self, data: bytes) -> dict:
        self.seen.append(data)
        return {'model': TAG_MODEL_ID, 'width': 100, 'height': 80, 'tags': [
            {'tag': data.decode(), 'category': 'Things', 'score': 0.9}]}


class PipelineTest(unittest.TestCase):
    def setUp(self):
        self.analyser = FakePod(ANALYSER_WEB_ID, 'analyser-key')
        self.client = FakeSolidClient()
        for pod in (self.analyser, FakePod(ALICE), FakePod(BOB)):
            self._seed_keys(pod)

        self.inbox = paths.data_url(ALICE, APP, '.faces-inbox') + '/'
        self.folder_key = crypto.random_key()
        self.tag_inbox = paths.data_url(ALICE, APP, '.tags-inbox') + '/'
        self.tag_key = crypto.random_key()
        self._share_with_analyser(self.inbox, self.folder_key)

        self.config = Config(
            analyser=AnalyserConfig(web_id=ANALYSER_WEB_ID, app_dir_name=APP,
                                    server_url=SERVER,
                                    security_key='analyser-key',
                                    client_id='id', client_secret='secret'),
            inbox=InboxConfig(),
            watch=WatchConfig(),
            engine=EngineConfig(models_dir=Path('.')),
            tags=TagConfig(models_dir=Path('.')),
        )
        self.engine = FakeEngine()
        self.tagger = FakeTagger()
        self.service = AnalyserService(self.config, self.client,
                                       PodKeys(self.client, self.config),
                                       self.engine, self.tagger)

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
        unique_id = crypto.unique_resource_id(resource_url, ANALYSER_WEB_ID)
        entry = turtle.shared_keys_document(
            shared_url,
            unique_id,
            crypto.rsa_encrypt(public, resource_url),
            crypto.rsa_encrypt(public, 'read,write'),
            crypto.rsa_encrypt(public, base64.b64encode(key).decode()),
        )
        graph = turtle.parse(self.client.resources[shared_url])

        # Sharing again replaces the entry, as revoking and granting does.

        for subject in set(graph.subjects()):
            if str(subject).endswith(unique_id):
                graph.remove((subject, None, None))
        graph.parse(data=entry, format='turtle')
        self.client.resources[shared_url] = graph.serialize(format='turtle')

    def share_tags(self) -> None:
        """Share Alice's tag inbox, as Tag Photos does once the photos are in
        it. Each call is a new request."""

        self._share_with_analyser(self.tag_inbox, self.tag_key)

    def leave(self, key: str, image: bytes, *, tags: bool = False) -> str:
        """Leave a photo in Alice's face inbox, or tag inbox, as PhotoPod
        does."""

        inbox, folder_key, inbox_path, request = (
            (self.tag_inbox, self.tag_key, TAG_INBOX_PATH, TAG_REQUEST_FORMAT)
            if tags else
            (self.inbox, self.folder_key, INBOX_PATH, REQUEST_FORMAT))
        url = f'{inbox}{key}.enc.ttl'
        self.client.resources[url] = encrypted_resource(
            url,
            {'format': request, 'version': 1,
             'image': base64.b64encode(image).decode()},
            folder_key,
            inherit_from=inbox_path,
        )
        return url

    def answer(self, key: str, *, tags: bool = False) -> dict:
        """Open the answer for [key] as PhotoPod's readPod() does: by the
        folder its inheritKeyFrom names, with Alice's own folder key."""

        inbox, folder_key, inbox_path, suffix = (
            (self.tag_inbox, self.tag_key, TAG_INBOX_PATH, TAG_RESULT_SUFFIX)
            if tags else
            (self.inbox, self.folder_key, INBOX_PATH, RESULT_SUFFIX))
        url = f'{inbox}{key}{suffix}'
        fields = turtle.triple_map(self.client.resources[url], base=url)[url]
        self.assertEqual(
            turtle.single(fields[paths.APPS_TERMS + 'inheritKeyFrom']),
            inbox_path)
        self.assertEqual(turtle.single(fields[paths.APPS_TERMS + 'path']),
                         f'{inbox_path}{key}{suffix}')
        return json.loads(crypto.aes_ctr_decrypt(
            turtle.single(fields[paths.APPS_TERMS + 'encData']),
            folder_key,
            base64.b64decode(turtle.single(fields[paths.APPS_TERMS + 'iv']))))

    # -- Looks -------------------------------------------------------------

    def test_answers_each_photo_in_the_users_own_inbox(self):
        a = self.leave('a' * 32, b'photo a')
        b = self.leave('b' * 32, b'photo b')

        reports = self.service.respond()

        self.assertEqual([(r.web_id, r.kind, r.analysed, r.failed)
                          for r in reports], [(ALICE, 'faces', 2, 0)])
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

        # Once every photo is answered, PhotoPod is told so.
        self.assertEqual(self.client.resources[f'{self.inbox}done'], 'done\n')

    def test_a_request_is_answered_once(self):
        self.leave('a' * 32, b'photo a')
        self.service.respond()

        # A photo left without asking again is not looked at: the inbox is
        # not read again until it is shared again.
        self.leave('b' * 32, b'photo b')
        self.assertEqual(self.service.respond(), [])
        self.assertEqual(self.engine.seen, [b'photo a'])

        self._share_with_analyser(self.inbox, self.folder_key)
        self.assertEqual(len(self.service.respond()), 1)
        self.assertEqual(self.engine.seen, [b'photo a', b'photo b'])

    def test_a_pod_that_has_not_asked_is_not_read(self):
        bob_inbox = paths.data_url(BOB, APP, '.faces-inbox') + '/'
        self.client.resources[bob_inbox + 'x' * 32 + '.enc.ttl'] = 'unread'
        self.client.private_urls.add(self.inbox)
        self.service.respond()
        self.assertEqual(self.engine.seen, [])

    def test_a_photo_the_key_cannot_open_is_left_unanswered(self):
        url = self.leave('a' * 32, b'photo a')
        self.client.resources[url] = encrypted_resource(
            url, {'format': REQUEST_FORMAT, 'version': 1, 'image': ''},
            crypto.random_key(), inherit_from=INBOX_PATH)

        report = self.service.run(ALICE)

        self.assertEqual((report.analysed, report.failed), (0, 0))
        self.assertEqual(len(report.errors), 1)
        self.assertIn(url, self.client.resources)
        self.assertNotIn(f'{self.inbox}{"a" * 32}{RESULT_SUFFIX}',
                         self.client.resources)

    def test_watching_answers_on_each_notification(self):
        self.client.resources[f'{SERVER}/Analyser/.well-known/solid'] = (
            f'@prefix notify: <{notify.NOTIFY}> .\n'
            f'<{SERVER}/Analyser/> notify:subscription <{SERVER}/ws/> .\n'
            f'<{SERVER}/ws/> notify:channelType notify:WebSocketChannel2023 .\n')
        shared_keys = paths.shared_key_url(ANALYSER_WEB_ID, APP)

        def listen(receive_from):
            self.assertEqual(receive_from, 'wss://server/ws/1')
            self.leave('b' * 32, b'photo b')
            self._share_with_analyser(self.inbox, self.folder_key)
            yield 'Update'
            raise KeyboardInterrupt

        self.leave('a' * 32, b'photo a')
        with self.assertRaises(KeyboardInterrupt):
            self.service.watch(listen)

        self.assertEqual(self.client.subscriptions,
                         [(f'{SERVER}/ws/', shared_keys)])
        # The request made before listening, then the one notified.
        self.assertEqual(self.engine.seen, [b'photo a', b'photo b'])

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
        self.assertEqual(self.service.respond(), [])

    def test_tags_are_answered_only_when_the_tag_inbox_is_shared(self):
        self.leave('a' * 32, b'photo a')
        photo = self.leave('b' * 32, b'Beach', tags=True)
        self.service.respond()
        self.assertEqual(self.tagger.seen, [])
        self.assertIn(photo, self.client.resources)

        self.share_tags()
        reports = self.service.respond()
        self.assertEqual([(r.kind, r.analysed) for r in reports],
                         [('tags', 1)])
        answer = self.answer('b' * 32, tags=True)
        self.assertEqual(answer['format'], TAG_RESULT_FORMAT)
        self.assertEqual(answer['model'], TAG_MODEL_ID)
        self.assertEqual(answer['tags'][0]['tag'], 'Beach')
        self.assertNotIn('faces', answer)
        self.assertNotIn(photo, self.client.resources)
        self.assertEqual(self.client.resources[f'{self.tag_inbox}done'],
                         'done\n')
        self.assertEqual(self.engine.seen, [b'photo a'])

    def test_a_face_request_in_the_tag_inbox_is_refused(self):
        url = f'{self.tag_inbox}{"c" * 32}.enc.ttl'
        self.client.resources[url] = encrypted_resource(
            url, {'format': REQUEST_FORMAT, 'version': 1, 'image': ''},
            self.tag_key, inherit_from=TAG_INBOX_PATH)
        self.share_tags()
        report = self.service.run(ALICE, 'tags')
        self.assertEqual(report.failed, 1)
        self.assertIn('failed', self.answer('c' * 32, tags=True))

    def test_tags_answers_are_not_mistaken_for_photos(self):
        self.leave('d' * 32, b'Dog', tags=True)
        self.share_tags()
        self.service.respond()

        # Asked again with only the answer left: nothing is analysed.
        self.share_tags()
        reports = self.service.respond()
        self.assertEqual([(r.kind, r.analysed, r.failed) for r in reports],
                         [('tags', 0, 0)])
        self.assertEqual(self.tagger.seen, [b'Dog'])

    def test_tagging_turned_off_leaves_the_tag_inboxes_alone(self):
        self.leave('e' * 32, b'Cat', tags=True)
        self.share_tags()
        service = AnalyserService(self.config, self.client,
                                  self.service.keys, self.engine)
        self.assertNotIn('tags', [r.kind for r in service.respond()])
        self.assertEqual(self.tagger.seen, [])
        with self.assertRaises(NotShared):
            service.run(ALICE, 'tags')

    def test_the_shared_keys_are_opened_once_while_unchanged(self):
        from unittest import mock

        self.service.keys.shared_resources()
        with mock.patch('face_analyser.keys.crypto.rsa_decrypt') as decrypt:
            self.service.keys.shared_resources()
        decrypt.assert_not_called()

if __name__ == '__main__':
    unittest.main()
