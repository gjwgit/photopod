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

from __future__ import annotations

import hashlib
import logging
import os
import urllib.request
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger(__name__)

_ZOO = 'https://github.com/opencv/opencv_zoo/raw/main/models'


@dataclass(frozen=True)
class Model:
    """One model file: where it comes from, and the SHA-256 it must have, so
    that a truncated or tampered download is never loaded."""

    file_name: str
    url: str
    sha256: str


# YuNet, OpenCV's face detector (MIT licence, 0.2 MB). It finds each face and
# the five landmarks the recogniser aligns it by.

DETECTOR = Model(
    'face_detection_yunet_2023mar.onnx',
    f'{_ZOO}/face_detection_yunet/face_detection_yunet_2023mar.onnx',
    '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4',
)

# SFace, OpenCV's face recogniser (Apache 2.0 licence, 37 MB). It turns an
# aligned face into 128 numbers that lie close together for one person.

RECOGNISER = Model(
    'face_recognition_sface_2021dec.onnx',
    f'{_ZOO}/face_recognition_sface/face_recognition_sface_2021dec.onnx',
    '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
)


class ModelError(Exception):
    """Raised when a model cannot be found, fetched or verified."""


def _digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def ensure(model: Model, folder: Path, *, download: bool = True) -> Path:
    """The local path of [model] in [folder], fetching it when it is missing.

    A file that is there but does not have the pinned digest is fetched
    again rather than loaded.
    """

    folder.mkdir(parents=True, exist_ok=True)
    path = folder / model.file_name
    if path.exists() and _digest(path) == model.sha256:
        return path
    if not download:
        raise ModelError(
            f'{path} is missing or damaged. Run ./run.sh fetch-models.'
        )

    log.info('Downloading %s', model.url)
    partial = path.with_suffix(path.suffix + '.part')
    try:
        with urllib.request.urlopen(model.url, timeout=120) as response:
            partial.write_bytes(response.read())
    except OSError as e:
        partial.unlink(missing_ok=True)
        raise ModelError(f'Could not download {model.file_name}: {e}') from e

    if _digest(partial) != model.sha256:
        partial.unlink(missing_ok=True)
        raise ModelError(f'{model.file_name} did not download intact.')

    # Written beside the final name and then renamed, so that an interrupted
    # download never leaves a partial model to be loaded next time.

    os.replace(partial, path)
    return path


def ensure_all(folder: Path, *, download: bool = True) -> tuple[Path, Path]:
    """The paths of the detector and the recogniser, in that order."""

    return (
        ensure(DETECTOR, folder, download=download),
        ensure(RECOGNISER, folder, download=download),
    )
