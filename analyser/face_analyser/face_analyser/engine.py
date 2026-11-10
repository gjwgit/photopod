"""Face detection (YuNet) and recognition (SFace) through OpenCV.

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

# This is the analysis PhotoPod used to run on the device through opencv_dart
# (lib/services/face_engine_native.dart before the move to this service), done
# with the same models and the same steps, so that the embeddings already kept
# in users' Pods stay comparable with the ones this service produces.

from __future__ import annotations

import base64
import os
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any

# The most pixels a decoded upload may have, so that a few kilobytes of
# hostile PNG cannot make the service allocate gigabytes. OpenCV reads the
# limit from the environment when it is imported, and refuses a larger
# picture before decoding it.

os.environ.setdefault('OPENCV_IO_MAX_IMAGE_PIXELS', str(60_000_000))

import cv2  # noqa: E402
import numpy as np

from . import MODEL_ID, models


@dataclass
class EngineConfig:
    """How the engine judges and pictures the faces it finds."""

    models_dir: Path

    # How sure YuNet must be before a face counts. Its own default, which
    # keeps patterned fabric and the faces on posters out of People.

    min_score: float = 0.9

    # The smallest face, in pixels of the picture analysed, worth recognising.
    # Below this SFace has too little to go on.

    min_face_side: int = 32

    # The longest side a picture is analysed at. PhotoPod sends its large
    # rendition, which is already this size; anything bigger is brought down.

    max_side: int = 2048

    # The side of the square JPEG returned of each face: sharp enough for
    # the portraits People shows, small enough (about 4 KB) to keep in the Pod.

    face_image_side: int = 96

    # How much room is left around a face in its picture, as a multiple of
    # the face's size, so that the picture shows the head.

    face_image_margin: float = 1.6


class ImageError(ValueError):
    """Raised when an upload is not a picture the engine can read."""


class FaceEngine:
    """Both models, loaded once and shared by every request.

    OpenCV's DNN networks keep per-call state, so one engine serves one
    picture at a time; a lock makes the threaded HTTP server safe. Running
    more worker processes is how the service scales.
    """

    def __init__(self, config: EngineConfig, *, download: bool = True):
        self.config = config
        detector, recogniser = models.ensure_all(
            config.models_dir, download=download
        )
        self._detector = cv2.FaceDetectorYN.create(
            str(detector), '', (320, 320), config.min_score
        )
        self._recogniser = cv2.FaceRecognizerSF.create(str(recogniser), '')
        self._lock = threading.Lock()

    @property
    def model_id(self) -> str:
        return MODEL_ID

    def analyse(self, data: bytes) -> dict[str, Any]:
        """The faces in [data], an encoded JPEG, PNG or similar.

        The answer, as PhotoPod reads it:

            {"model": ..., "width": w, "height": h, "faces": [
                {"box": [left, top, width, height],   # fractions of w and h
                 "score": 0.97,
                 "embedding": "<base64 of 128 little-endian float32>",
                 "image": "<base64 JPEG>"}]}
        """

        image = self._decode(data)
        with self._lock:
            faces = self._faces(image)
        height, width = image.shape[:2]
        return {
            'model': MODEL_ID,
            'width': width,
            'height': height,
            'faces': faces,
        }

    def _decode(self, data: bytes) -> np.ndarray:
        if not data:
            raise ImageError('The upload is empty.')
        buffer = np.frombuffer(data, dtype=np.uint8)

        # IMREAD_COLOR applies the EXIF orientation, so an original is
        # analysed the way up it is shown, as the renditions already are.

        try:
            image = cv2.imdecode(buffer, cv2.IMREAD_COLOR)
        except cv2.error as e:
            raise ImageError(f'The picture could not be read: {e}') from e
        if image is None:
            raise ImageError(
                'The upload is not a picture OpenCV can read, or is too large.'
            )

        longest = max(image.shape[:2])
        if longest > self.config.max_side:
            scale = self.config.max_side / longest
            image = cv2.resize(
                image,
                (
                    round(image.shape[1] * scale),
                    round(image.shape[0] * scale),
                ),
                interpolation=cv2.INTER_AREA,
            )
        return image

    def _faces(self, image: np.ndarray) -> list[dict[str, Any]]:
        height, width = image.shape[:2]
        self._detector.setInputSize((width, height))
        _, detections = self._detector.detect(image)
        if detections is None:
            return []

        # Each row is x, y, width, height, five landmarks as x, y pairs, and
        # the score.

        found = []
        for row in detections:
            x, y, w, h = (float(v) for v in row[:4])
            if min(w, h) < self.config.min_face_side:
                continue
            aligned = self._recogniser.alignCrop(image, row)
            feature = self._recogniser.feature(aligned)
            found.append(
                {
                    'box': [
                        round(x / width, 4),
                        round(y / height, 4),
                        round(w / width, 4),
                        round(h / height, 4),
                    ],
                    'score': round(float(row[14]), 3),
                    'embedding': _encode_embedding(feature),
                    'image': self._face_image(image, x, y, w, h),
                }
            )
        return found

    # A square JPEG of the face at [x, y, w, h], with some room around it,
    # cut from [image] and scaled to face_image_side.

    def _face_image(
        self, image: np.ndarray, x: float, y: float, w: float, h: float
    ) -> str | None:
        rows, cols = image.shape[:2]
        side = int(
            min(max(w, h) * self.config.face_image_margin, min(cols, rows))
        )
        if side <= 0:
            return None
        left = int(min(max(x + w / 2 - side / 2, 0), cols - side))
        top = int(min(max(y + h / 2 - side / 2, 0), rows - side))
        region = image[top : top + side, left : left + side]
        small = cv2.resize(
            region,
            (self.config.face_image_side, self.config.face_image_side),
            interpolation=cv2.INTER_AREA,
        )
        ok, jpeg = cv2.imencode('.jpg', small, [cv2.IMWRITE_JPEG_QUALITY, 85])
        return base64.b64encode(jpeg.tobytes()).decode('ascii') if ok else None


def _encode_embedding(feature: np.ndarray) -> str:
    """The embedding scaled to unit length, as base64 of little-endian
    float32, which is how PhotoPod's faces file keeps it."""

    values = feature.reshape(-1).astype('<f4')
    norm = float(np.linalg.norm(values))
    if norm > 0:
        values = (values / norm).astype('<f4')
    return base64.b64encode(values.tobytes()).decode('ascii')
