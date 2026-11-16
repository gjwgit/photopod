"""The two ONNX models the face analyser runs on, fetched once per host.

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

# The models are InsightFace's `buffalo_l` pack, the set Immich also uses:
#
#   det_10g.onnx     SCRFD-10GF, the face detector, with five landmarks
#   w600k_r50.onnx   ArcFace ResNet-50 trained on WebFace600K, the recogniser
#
# InsightFace publishes them only as one archive, with three more models this
# service has no use for, so the archive is fetched once, checked, and only
# the two kept.
#
# Licence: InsightFace's code is MIT, but its pretrained models are released
# "for non-commercial research purposes only". See README.md, section
# "Models and licence", before any commercial deployment.
#
# The tags come from Google's SigLIP ViT-B/16 (WebLI, 224 pixels), released
# under the Apache License 2.0, in the ONNX export Immich publishes. Only its
# image half is needed to tag photos; the text half is fetched only by
# `embed-tags`, which describes the tag vocabulary once (see tagger.py).

from __future__ import annotations

import hashlib
import io
import logging
import os
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger(__name__)

PACK_URL = ('https://github.com/deepinsight/insightface/releases/download/'
            'v0.7/buffalo_l.zip')
PACK_SHA256 = '80ffe37d8a5940d59a7384c201a2a38d4741f2f3c51eef46ebb28218a7b0ca2f'


@dataclass(frozen=True)
class Model:
    """One model file and the SHA-256 it must have, so that a truncated or
    tampered file is never loaded."""

    file_name: str
    sha256: str


DETECTOR = Model(
    'det_10g.onnx',
    '5838f7fe053675b1c7a08b633df49e7af5495cee0493c7dcf6697200b85b5b91',
)

RECOGNISER = Model(
    'w600k_r50.onnx',
    '4c06341c33c2ca1f86781dab0e829f88ad5b64be9fba56e56bc9ebdefc619e43',
)


# The SigLIP export, pinned to one revision so that what is fetched is what
# the digests below describe.

SIGLIP_URL = ('https://huggingface.co/immich-app/ViT-B-16-SigLIP__webli/'
              'resolve/c3b037a9ef99ed5f116440790f1e098fb388db49/')
SIGLIP_DIR = 'siglip-b16-webli'


@dataclass(frozen=True)
class Download:
    """One file fetched on its own, where it comes from and what it holds."""

    remote: str
    file_name: str
    sha256: str
    megabytes: int


TAG_IMAGE_MODEL = Download(
    'visual/model.onnx', 'visual.onnx',
    '0981d03d194baa6153106d41b5a5ca73faa514e8d9a007a3332eecb63be2c74a', 372)

TAG_TEXT_MODEL = Download(
    'textual/model.onnx', 'textual.onnx',
    '3983f96348daba5024f5e3085d2ea8cc67c11ce553e4061f193e8ea37aabd792', 441)

TAG_TOKENISER = Download(
    'textual/tokenizer.json', 'tokenizer.json',
    'ec6fe74c37f2a65be3857ef5e8fbca7662ebb15fcfa569a845a59958db969f76', 3)


class ModelError(Exception):
    """Raised when a model cannot be found, fetched or verified."""


def _digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _file_digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def _intact(model: Model, folder: Path) -> bool:
    path = folder / model.file_name
    return path.exists() and _file_digest(path) == model.sha256


def _fetch_pack(folder: Path) -> None:
    log.info('Downloading %s (275 MB)', PACK_URL)
    try:
        with urllib.request.urlopen(PACK_URL, timeout=600) as response:
            data = response.read()
    except OSError as e:
        raise ModelError(f'Could not download {PACK_URL}: {e}') from e
    if _digest(data) != PACK_SHA256:
        raise ModelError('buffalo_l.zip did not download intact.')

    with zipfile.ZipFile(io.BytesIO(data)) as pack:
        names = {Path(n).name: n for n in pack.namelist()}
        for model in (DETECTOR, RECOGNISER):
            member = names.get(model.file_name)
            if member is None:
                raise ModelError(f'buffalo_l.zip holds no {model.file_name}.')
            content = pack.read(member)
            if _digest(content) != model.sha256:
                raise ModelError(f'{model.file_name} in buffalo_l.zip is not '
                                 'the one expected.')

            # Written beside the final name and then renamed, so that an
            # interrupted write never leaves a partial model to be loaded.

            path = folder / model.file_name
            partial = path.with_suffix(path.suffix + '.part')
            partial.write_bytes(content)
            os.replace(partial, path)


def ensure_all(folder: Path, *, download: bool = True) -> tuple[Path, Path]:
    """The paths of the detector and the recogniser, in that order,
    fetching them when either is missing or damaged."""

    folder.mkdir(parents=True, exist_ok=True)
    if not (_intact(DETECTOR, folder) and _intact(RECOGNISER, folder)):
        if not download:
            raise ModelError(
                f'The face models in {folder} are missing or damaged. Run '
                './run.sh fetch-models.')
        _fetch_pack(folder)
    return folder / DETECTOR.file_name, folder / RECOGNISER.file_name


def _fetch(item: Download, folder: Path) -> None:
    url = SIGLIP_URL + item.remote
    log.info('Downloading %s (%d MB)', url, item.megabytes)
    path = folder / item.file_name
    partial = path.with_suffix(path.suffix + '.part')
    h = hashlib.sha256()
    try:
        with urllib.request.urlopen(url, timeout=600) as response, \
                partial.open('wb') as out:
            for chunk in iter(lambda: response.read(1 << 20), b''):
                h.update(chunk)
                out.write(chunk)
    except OSError as e:
        partial.unlink(missing_ok=True)
        raise ModelError(f'Could not download {url}: {e}') from e
    if h.hexdigest() != item.sha256:
        partial.unlink(missing_ok=True)
        raise ModelError(f'{url} did not download intact.')
    os.replace(partial, path)


def ensure_siglip(folder: Path, items: tuple[Download, ...], *,
                  download: bool = True) -> tuple[Path, ...]:
    """The paths of [items] of the SigLIP export, in order, fetching any
    that is missing or damaged."""

    folder = folder / SIGLIP_DIR
    folder.mkdir(parents=True, exist_ok=True)
    for item in items:
        path = folder / item.file_name
        if path.exists() and _file_digest(path) == item.sha256:
            continue
        if not download:
            raise ModelError(
                f'The tag model {path} is missing or damaged. Run '
                './run.sh fetch-models.')
        _fetch(item, folder)
    return tuple(folder / item.file_name for item in items)
