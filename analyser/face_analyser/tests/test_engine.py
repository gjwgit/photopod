"""The analysis, on PhotoPod's own sample photos.

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

# Needs the two models in var/models (./setup.sh or ./run.sh fetch-models);
# skipped without them, since the suite is meant to run offline.

from __future__ import annotations

import base64
import unittest
from pathlib import Path

import numpy as np

from face_analyser import MODEL_ID
from face_analyser.engine import EngineConfig, FaceEngine, ImageError
from face_analyser.models import ModelError

ROOT = Path(__file__).resolve().parents[1]
SAMPLES = ROOT.parents[1] / 'assets' / 'demo'
MODELS = ROOT / 'var' / 'models'


def _engine() -> FaceEngine:
    try:
        return FaceEngine(EngineConfig(models_dir=MODELS), download=False)
    except ModelError as e:
        raise unittest.SkipTest(str(e)) from e


def _embedding(face: dict) -> np.ndarray:
    return np.frombuffer(base64.b64decode(face['embedding']), dtype='<f4')


class EngineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not SAMPLES.exists():
            raise unittest.SkipTest('PhotoPod sample photos not found')
        cls.engine = _engine()

    def faces(self, name: str) -> list[dict]:
        result = self.engine.analyse((SAMPLES / name).read_bytes())
        self.assertEqual(result['model'], MODEL_ID)
        return result['faces']

    def test_one_face_in_a_portrait(self):
        faces = self.faces('john_mather_2012.jpg')
        self.assertEqual(len(faces), 1)
        face = faces[0]
        self.assertGreaterEqual(face['score'], 0.9)
        self.assertTrue(all(0 <= v <= 1 for v in face['box']))
        embedding = _embedding(face)
        self.assertEqual(embedding.shape, (128,))
        self.assertAlmostEqual(float(np.linalg.norm(embedding)), 1.0, places=4)
        jpeg = base64.b64decode(face['image'])
        self.assertEqual(jpeg[:2], b'\xff\xd8')

    def test_no_face_in_a_landscape(self):
        self.assertEqual(self.faces('matterhorn.jpg'), [])

    def test_same_person_is_closer_than_strangers(self):
        # 0.363 is the threshold PhotoPod files faces by.
        mather = [_embedding(self.faces(n)[0])
                  for n in ('john_mather_2012.jpg', 'john_mather_2016.jpg')]
        riess = _embedding(self.faces('adam_riess_2008.jpg')[0])
        self.assertGreater(float(mather[0] @ mather[1]), 0.363)
        self.assertLess(float(mather[0] @ riess), 0.363)

    def test_refuses_what_is_not_a_picture(self):
        with self.assertRaises(ImageError):
            self.engine.analyse(b'')
        with self.assertRaises(ImageError):
            self.engine.analyse(b'not a picture at all')


if __name__ == '__main__':
    unittest.main()
