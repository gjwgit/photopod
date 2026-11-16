"""Tests for the tag engine, with the real model, on PhotoPod's samples.

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

# Needs the SigLIP image model in var/models (./setup.sh or ./run.sh
# fetch-models); skipped without it, since the suite is meant to run offline.

from __future__ import annotations

import unittest
from pathlib import Path

from face_analyser.models import ModelError
from face_analyser.tagger import EMBEDDINGS, TagConfig, TagEngine, Vocabulary

ROOT = Path(__file__).resolve().parents[1]
SAMPLES = ROOT.parents[1] / 'assets' / 'demo'
MODELS = ROOT / 'var' / 'models'


class VocabularyTest(unittest.TestCase):
    def test_the_shipped_descriptions_match_the_vocabulary(self):
        import numpy as np

        vocabulary = Vocabulary.load()
        stored = np.load(EMBEDDINGS)
        self.assertEqual(str(stored['digest']), vocabulary.digest)
        self.assertEqual(stored['embeddings'].shape,
                         (len(vocabulary.tags), 768))

    def test_every_tag_is_named_once(self):
        names = [tag for _, tag, _ in Vocabulary.load().tags]
        self.assertEqual(len(names), len(set(names)))


class TagEngineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not SAMPLES.exists():
            raise unittest.SkipTest('PhotoPod sample photos not found')
        try:
            cls.engine = TagEngine(TagConfig(models_dir=MODELS),
                                   download=False)
        except ModelError as e:
            raise unittest.SkipTest(str(e)) from e

    def tags(self, name: str) -> list[str]:
        result = self.engine.analyse((SAMPLES / name).read_bytes())
        self.assertEqual(result['model'], self.engine.model_id)
        return [t['tag'] for t in result['tags']]

    def test_landscapes_are_tagged_with_what_they_show(self):
        self.assertEqual(self.tags('grand_canyon.jpg')[0], 'Canyon')
        self.assertEqual(self.tags('great_ocean_road.jpg')[0], 'Beach')
        self.assertEqual(self.tags('iceland_waterfall.jpg')[0], 'Waterfall')
        self.assertEqual(self.tags('perito_moreno.jpg')[0], 'Glacier')
        self.assertEqual(self.tags('sahara.jpg')[0], 'Desert')
        self.assertIn('Mountains', self.tags('matterhorn.jpg'))

    def test_a_portrait_is_tagged_as_one(self):
        self.assertEqual(self.tags('john_mather_2016.jpg')[0], 'Portrait')

    def test_tags_are_few_and_best_first(self):
        result = self.engine.analyse(
            (SAMPLES / 'moraine_lake.jpg').read_bytes())
        scores = [t['score'] for t in result['tags']]
        self.assertLessEqual(len(scores), self.engine.config.max_tags)
        self.assertEqual(scores, sorted(scores, reverse=True))
        self.assertTrue(all(t['category'] for t in result['tags']))


if __name__ == '__main__':
    unittest.main()
