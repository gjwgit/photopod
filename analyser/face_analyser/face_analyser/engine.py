"""Face detection (SCRFD) and recognition (ArcFace) through ONNX Runtime.

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

# InsightFace's buffalo_l models (see models.py), run directly through ONNX
# Runtime rather than through the `insightface` package, which needs a C
# compiler to install and brings in far more than is used here. The steps are
# InsightFace's own (`model_zoo/scrfd.py`, `model_zoo/arcface_onnx.py`,
# `utils/face_align.py`):
#
#   1. SCRFD finds each face, with five landmarks: the eyes, the nose tip and
#      the corners of the mouth;
#   2. the face is turned and scaled so that those landmarks fall on ArcFace's
#      template, in a 112 x 112 picture;
#   3. ArcFace describes it as 512 numbers, scaled here to unit length, that
#      lie close together for one person.

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
import numpy as np  # noqa: E402
import onnxruntime as ort  # noqa: E402

from . import MODEL_ID, models  # noqa: E402

# Where ArcFace expects the five landmarks to be, in its 112 x 112 input.

_ARCFACE_TEMPLATE = np.array([
    [38.2946, 51.6963],
    [73.5318, 51.5014],
    [56.0252, 71.7366],
    [41.5493, 92.3655],
    [70.7299, 92.2041],
], dtype=np.float32)

# SCRFD-10GF looks at three scales, each cell of each with two anchors.

_STRIDES = (8, 16, 32)
_ANCHORS = 2


@dataclass
class EngineConfig:
    """How the engine judges and pictures the faces it finds."""

    models_dir: Path

    # How sure SCRFD must be before a face counts. InsightFace's own default
    # is 0.5; a little higher keeps faces on posters and in patterned fabric
    # out of People without losing real ones, which score 0.7 and above.

    min_score: float = 0.6

    # The smallest face, in pixels of the picture analysed, worth recognising.
    # ArcFace works on 112 pixels; below about a fifth of that it has too
    # little to go on.

    min_face_side: int = 24

    # The side of the square SCRFD looks at. 640 is what it was trained for.

    detect_side: int = 640

    # How much two boxes may overlap and still be two faces.

    nms_overlap: float = 0.4

    # The longest side a picture is kept at. PhotoPod leaves its 2048 pixel
    # large rendition; anything bigger is brought down.

    max_side: int = 2048

    # The side of the square JPEG kept of each face: sharp enough for the
    # portraits People shows, small enough (about 4 KB) to keep in the Pod.

    face_image_side: int = 96

    # How much room is left around a face in its picture, as a multiple of
    # the face's size, so that the picture shows the head.

    face_image_margin: float = 1.6

    # Threads ONNX Runtime may use for one picture. 0 lets it decide.

    threads: int = 0


class ImageError(ValueError):
    """Raised when an upload is not a picture the engine can read."""


class FaceEngine:
    """Both models, loaded once and used for every photo, one at a time."""

    def __init__(self, config: EngineConfig, *, download: bool = True):
        self.config = config
        detector, recogniser = models.ensure_all(
            config.models_dir, download=download)
        options = ort.SessionOptions()
        if config.threads:
            options.intra_op_num_threads = config.threads
        providers = ['CPUExecutionProvider']
        self._detector = ort.InferenceSession(
            str(detector), options, providers=providers)
        self._recogniser = ort.InferenceSession(
            str(recogniser), options, providers=providers)
        self._detector_input = self._detector.get_inputs()[0].name
        self._recogniser_input = self._recogniser.get_inputs()[0].name
        self._centres: dict[tuple[int, int, int], np.ndarray] = {}
        self._lock = threading.Lock()

    @property
    def model_id(self) -> str:
        return MODEL_ID

    def analyse(self, data: bytes) -> dict[str, Any]:
        """The faces in [data], an encoded JPEG, PNG or similar.

            {"model": ..., "width": w, "height": h, "faces": [
                {"box": [left, top, width, height],   # fractions of w and h
                 "score": 0.97,
                 "embedding": "<base64 of 512 little-endian float32>",
                 "image": "<base64 JPEG>"}]}
        """

        image = self._decode(data)
        with self._lock:
            faces = self._faces(image)
        height, width = image.shape[:2]
        return {'model': MODEL_ID, 'width': width, 'height': height,
                'faces': faces}

    # -- Reading the picture ---------------------------------------------

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
                'The upload is not a picture OpenCV can read, or is too large.')

        longest = max(image.shape[:2])
        if longest > self.config.max_side:
            scale = self.config.max_side / longest
            image = cv2.resize(
                image,
                (round(image.shape[1] * scale), round(image.shape[0] * scale)),
                interpolation=cv2.INTER_AREA)
        return image

    # -- Finding the faces ------------------------------------------------

    def _faces(self, image: np.ndarray) -> list[dict[str, Any]]:
        height, width = image.shape[:2]
        found = []
        for box, landmarks, score in self._detect(image):
            x1, y1, x2, y2 = (float(v) for v in box)
            w, h = x2 - x1, y2 - y1
            if min(w, h) < self.config.min_face_side:
                continue
            found.append({
                'box': [round(max(x1, 0) / width, 4),
                        round(max(y1, 0) / height, 4),
                        round(min(w, width - max(x1, 0)) / width, 4),
                        round(min(h, height - max(y1, 0)) / height, 4)],
                'score': round(float(score), 3),
                'embedding': _encode_embedding(self._embed(image, landmarks)),
                'image': self._face_image(image, x1, y1, w, h),
            })
        return found

    def _detect(self, image: np.ndarray
                ) -> list[tuple[np.ndarray, np.ndarray, float]]:
        """SCRFD on [image], letterboxed into its square input: each face's
        box (x1, y1, x2, y2), its five landmarks and its score, in the
        pixels of [image]."""

        side = self.config.detect_side
        height, width = image.shape[:2]
        scale = min(side / width, side / height)
        resized = cv2.resize(image, (int(width * scale), int(height * scale)))
        square = np.zeros((side, side, 3), dtype=np.uint8)
        square[: resized.shape[0], : resized.shape[1]] = resized

        blob = cv2.dnn.blobFromImage(
            square, 1.0 / 128, (side, side), (127.5, 127.5, 127.5),
            swapRB=True)
        outputs = self._detector.run(None, {self._detector_input: blob})

        scores, boxes, points = [], [], []
        levels = len(_STRIDES)
        for index, stride in enumerate(_STRIDES):
            level_scores = outputs[index].reshape(-1)
            distances = outputs[index + levels].reshape(-1, 4) * stride
            offsets = outputs[index + 2 * levels].reshape(-1, 10) * stride
            centres = self._anchor_centres(side, side, stride)

            keep = np.where(level_scores >= self.config.min_score)[0]
            if keep.size == 0:
                continue
            c = centres[keep]
            d = distances[keep]
            boxes.append(np.stack([c[:, 0] - d[:, 0], c[:, 1] - d[:, 1],
                                   c[:, 0] + d[:, 2], c[:, 1] + d[:, 3]],
                                  axis=-1))
            o = offsets[keep].reshape(-1, 5, 2)
            points.append(c[:, None, :] + o)
            scores.append(level_scores[keep])

        if not scores:
            return []
        scores = np.concatenate(scores)
        boxes = np.concatenate(boxes) / scale
        points = np.concatenate(points) / scale
        keep = _nms(boxes, scores, self.config.nms_overlap)
        return [(boxes[i], points[i], float(scores[i])) for i in keep]

    def _anchor_centres(self, height: int, width: int, stride: int
                        ) -> np.ndarray:
        key = (height, width, stride)
        centres = self._centres.get(key)
        if centres is None:
            rows, cols = height // stride, width // stride
            grid = np.stack(np.mgrid[:rows, :cols][::-1], axis=-1)
            centres = (grid.astype(np.float32) * stride).reshape(-1, 2)
            centres = np.repeat(centres, _ANCHORS, axis=0)
            self._centres[key] = centres
        return centres

    # -- Describing a face ------------------------------------------------

    def _embed(self, image: np.ndarray, landmarks: np.ndarray) -> np.ndarray:
        """ArcFace's embedding of the face whose landmarks are [landmarks]."""

        transform, _ = cv2.estimateAffinePartial2D(
            landmarks.astype(np.float32), _ARCFACE_TEMPLATE, method=cv2.LMEDS)
        aligned = cv2.warpAffine(image, transform, (112, 112), borderValue=0.0)
        blob = cv2.dnn.blobFromImage(
            aligned, 1.0 / 127.5, (112, 112), (127.5, 127.5, 127.5),
            swapRB=True)
        return self._recogniser.run(
            None, {self._recogniser_input: blob})[0].reshape(-1)

    # A square JPEG of the face at [x, y, w, h], with some room around it,
    # cut from [image] and scaled to face_image_side.

    def _face_image(self, image: np.ndarray, x: float, y: float, w: float,
                    h: float) -> str | None:
        rows, cols = image.shape[:2]
        side = int(min(max(w, h) * self.config.face_image_margin,
                       min(cols, rows)))
        if side <= 0:
            return None
        left = int(min(max(x + w / 2 - side / 2, 0), cols - side))
        top = int(min(max(y + h / 2 - side / 2, 0), rows - side))
        region = image[top : top + side, left : left + side]
        small = cv2.resize(
            region,
            (self.config.face_image_side, self.config.face_image_side),
            interpolation=cv2.INTER_AREA)
        ok, jpeg = cv2.imencode('.jpg', small, [cv2.IMWRITE_JPEG_QUALITY, 85])
        return base64.b64encode(jpeg.tobytes()).decode('ascii') if ok else None


def _nms(boxes: np.ndarray, scores: np.ndarray, overlap: float) -> list[int]:
    """The boxes left after dropping each that overlaps a surer one by more
    than [overlap] (intersection over union), surest first."""

    x1, y1, x2, y2 = boxes.T
    areas = (x2 - x1 + 1) * (y2 - y1 + 1)
    order = scores.argsort()[::-1]
    keep = []
    while order.size:
        i = order[0]
        keep.append(int(i))
        xx1 = np.maximum(x1[i], x1[order[1:]])
        yy1 = np.maximum(y1[i], y1[order[1:]])
        xx2 = np.minimum(x2[i], x2[order[1:]])
        yy2 = np.minimum(y2[i], y2[order[1:]])
        inter = np.maximum(0.0, xx2 - xx1 + 1) * np.maximum(0.0, yy2 - yy1 + 1)
        iou = inter / (areas[i] + areas[order[1:]] - inter)
        order = order[1:][iou <= overlap]
    return keep


def _encode_embedding(feature: np.ndarray) -> str:
    """The embedding scaled to unit length, as base64 of little-endian
    float32, which is how PhotoPod's faces file keeps it."""

    values = feature.reshape(-1).astype('<f4')
    norm = float(np.linalg.norm(values))
    if norm > 0:
        values = (values / norm).astype('<f4')
    return base64.b64encode(values.tobytes()).decode('ascii')
