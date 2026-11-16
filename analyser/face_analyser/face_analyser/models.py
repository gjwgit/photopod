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
