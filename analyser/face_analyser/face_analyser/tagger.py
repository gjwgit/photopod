"""Tagging photos with what they show, from a fixed vocabulary.

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

# Tags come from SigLIP (see models.py), which describes a picture and a
# piece of text as points in one space, close together when the text says
# what the picture shows. Every tag in tag_vocabulary.json is described once,
# as "a photo of <its words>", and the descriptions are shipped beside it in
# tag_vocabulary.npz, so the service needs only the image half of the model.
#
# For each photo the engine
#
#   1. describes it, at the 224 x 224 pixels SigLIP looks at;
#   2. measures how close it lies to every tag, and turns those measures into
#      shares of one whole, sharply, so that the tags that fit stand out from
#      the many that do not;
#   3. keeps the few tags that both take a fair share and lie close enough in
#      their own right. A photo that fits nothing well gets no tags rather
#      than the least bad ones.
#
# Changing the vocabulary means running `./run.sh embed-tags`, which fetches
# the text half of the model, and raising the vocabulary's version, which
# PhotoPod files the tags by (`tagModelId` in lib/services/tags.dart).

from __future__ import annotations

import hashlib
import json
import string
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import onnxruntime as ort

from . import models
from .engine import ImageError, cv2, decode_image

VOCABULARY = Path(__file__).with_name('tag_vocabulary.json')
EMBEDDINGS = Path(__file__).with_name('tag_vocabulary.npz')

_SIDE = 224
_CONTEXT = 64
_END = 1


@dataclass
class TagConfig:
    """Whether photos are tagged, and how sure a tag must be."""

    models_dir: Path

    # Turn tagging off on a host with no room for the tag model; the tag
    # inboxes shared with the Analyser are then left alone.

    enabled: bool = True

    # The folder in PhotoPod's data folder users share for tagging. Must
    # match `tagInbox` in PhotoPod's lib/services/analyser_inbox.dart.

    folder: str = '.tags-inbox'

    # The share of the whole a tag must take, and how close it must lie in
    # its own right. On the sample photos a fitting tag takes 0.15 or more,
    # at 0.04 or closer; one that does not fit, under 0.05.

    min_share: float = 0.12
    min_similarity: float = 0.035

    # The most tags one photo is given.

    max_tags: int = 4

    # How sharply closeness is turned into shares: SigLIP's own scale.

    sharpness: float = 100.0

    # Threads ONNX Runtime may use for one picture. 0 lets it decide.

    threads: int = 0


@dataclass(frozen=True)
class Vocabulary:
    """Every tag, the category it is filed under, and the words for it."""

    version: int
    template: str
    tags: tuple[tuple[str, str, str], ...]  # (category, tag, words)

    @classmethod
    def load(cls, path: Path = VOCABULARY) -> Vocabulary:
        data = json.loads(path.read_text())
        return cls(
            version=int(data['version']),
            template=data['template'],
            tags=tuple((category, tag, words)
                       for category, entries in data['categories'].items()
                       for tag, words in entries.items()),
        )

    @property
    def model_id(self) -> str:
        """What the tags are filed by: the model and the vocabulary's
        version. It must match `tagModelId` in PhotoPod."""

        return f'siglip-b16-webli:tags-v{self.version}'

    @property
    def digest(self) -> str:
        """What the shipped descriptions were made from."""

        text = json.dumps([self.template, self.tags], ensure_ascii=False)
        return hashlib.sha256(text.encode()).hexdigest()

    def prompts(self) -> list[str]:
        return [self.template.format(words) for _, _, words in self.tags]


def _embeddings(vocabulary: Vocabulary) -> np.ndarray:
    try:
        stored = np.load(EMBEDDINGS)
    except OSError as e:
        raise models.ModelError(
            f'{EMBEDDINGS.name} is missing. Run ./run.sh embed-tags.') from e
    if str(stored['digest']) != vocabulary.digest:
        raise models.ModelError(
            f'{EMBEDDINGS.name} describes another vocabulary than '
            f'{VOCABULARY.name}. Run ./run.sh embed-tags.')
    return stored['embeddings'].astype(np.float32)


def _session(path: Path, threads: int) -> ort.InferenceSession:
    options = ort.SessionOptions()
    if threads:
        options.intra_op_num_threads = threads
    return ort.InferenceSession(str(path), options,
                                providers=['CPUExecutionProvider'])


class TagEngine:
    """The image half of SigLIP and the described vocabulary, loaded once."""

    def __init__(self, config: TagConfig, *, download: bool = True):
        self.config = config
        self.vocabulary = Vocabulary.load()
        self._tags = _embeddings(self.vocabulary)
        (image_model,) = models.ensure_siglip(
            config.models_dir, (models.TAG_IMAGE_MODEL,), download=download)
        self._model = _session(image_model, config.threads)
        self._input = self._model.get_inputs()[0].name
        self._lock = threading.Lock()

    @property
    def model_id(self) -> str:
        return self.vocabulary.model_id

    def analyse(self, data: bytes) -> dict[str, Any]:
        """The tags for [data], an encoded JPEG, PNG or similar.

            {"model": ..., "width": w, "height": h, "tags": [
                {"tag": "Beach", "category": "Nature", "score": 0.83}]}

        best first; `score` is the share of the whole the tag took.
        """

        image = decode_image(data, 2048)
        height, width = image.shape[:2]
        with self._lock:
            embedding = self._describe(image)
        return {'model': self.model_id, 'width': width, 'height': height,
                'tags': self._choose(self._tags @ embedding)}

    def _describe(self, image: np.ndarray) -> np.ndarray:
        # SigLIP was trained on pictures squashed to a square, not cropped.
        rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        rgb = cv2.resize(rgb, (_SIDE, _SIDE), interpolation=cv2.INTER_AREA)
        x = (rgb.astype(np.float32) / 127.5 - 1.0).transpose(2, 0, 1)[None]
        feature = self._model.run(None, {self._input: x})[0][0]
        norm = float(np.linalg.norm(feature))
        if not norm:
            raise ImageError('The picture could not be described.')
        return feature / norm

    def _choose(self, similarity: np.ndarray) -> list[dict[str, Any]]:
        weights = np.exp(self.config.sharpness
                         * (similarity - similarity.max()))
        shares = weights / weights.sum()
        chosen = []
        for i in np.argsort(-shares)[: max(0, self.config.max_tags)]:
            if (shares[i] < self.config.min_share
                    or similarity[i] < self.config.min_similarity):
                break
            category, tag, _ = self.vocabulary.tags[i]
            chosen.append({'tag': tag, 'category': category,
                           'score': round(float(shares[i]), 3)})
        return chosen


# -- Describing the vocabulary ---------------------------------------------


def _canonical(text: str) -> str:
    # How SigLIP's text was cleaned in training: lower case, no punctuation.
    text = text.lower().translate(str.maketrans('', '', string.punctuation))
    return ' '.join(text.split())


def embed_vocabulary(models_dir: Path) -> Path:
    """Describe every tag with the text half of SigLIP, fetching it if need
    be, and write the descriptions beside the vocabulary."""

    try:
        from tokenizers import Tokenizer
    except ImportError as e:
        raise models.ModelError(
            'embed-tags needs the tokenizers package: pip install '
            'tokenizers') from e

    text_model, tokeniser_file = models.ensure_siglip(
        models_dir, (models.TAG_TEXT_MODEL, models.TAG_TOKENISER))
    tokeniser = Tokenizer.from_file(str(tokeniser_file))
    session = _session(text_model, 0)
    name = session.get_inputs()[0].name

    vocabulary = Vocabulary.load()
    rows = []
    for prompt in vocabulary.prompts():
        ids = tokeniser.encode(_canonical(prompt)).ids[:_CONTEXT]
        ids += [_END] * (_CONTEXT - len(ids))
        feature = session.run(None, {name: np.array([ids], dtype=np.int32)})
        feature = feature[0][0]
        rows.append(feature / np.linalg.norm(feature))
    np.savez_compressed(EMBEDDINGS, embeddings=np.stack(rows).astype(np.float32),
                        digest=np.array(vocabulary.digest))
    return EMBEDDINGS
