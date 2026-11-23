/// TeePod's faces, as the answer the Pod Analyser would have written.
///
/// Copyright (C) 2026, Togaware Pty Ltd.
///
/// Licensed under the GNU General Public License, Version 3 (the "License").
///
/// License: https://opensource.org/license/gpl-3-0
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://opensource.org/license/gpl-3-0>.
///
/// Authors: Tony Chen

library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:photopod/models/face_book.dart';
import 'package:photopod/services/teepod/teepod_types.dart';

// TeePod runs the same models as the Pod Analyser, InsightFace's buffalo_l,
// so its embeddings sit beside those already in the faces file and the
// people already named are recognised. Only how sure a face must be, and
// how small it may be, differ between the two, and are made the Pod
// Analyser's here (min_score and min_face_side in its engine.py).

/// How sure the detector must be of a face. TeePod passes faces from 0.5.

const double minFaceScore = 0.6;

/// The smallest face kept, in pixels on its shorter side.

const double minFaceSide = 24;

/// The side of the small square picture kept of each face, for People and
/// Get Info, and how much room is left around the face in it.

const int faceImageSide = 96;
const double faceImageMargin = 1.6;

/// [answer], TeePod's faces in [picture], the picture it was sent, as the
/// JSON the Pod Analyser writes in the face inbox, which
/// `FaceResult.parse` reads. TeePod does not send back a picture of each
/// face, so it is cut out of [picture] here.
///
/// Decoding and cutting take a while, so this is meant to run in an
/// isolate: see `compute`.

String faceAnswerFromTeePod(({TeePodAnswer answer, Uint8List picture}) input) {
  final answer = input.answer;
  final result = <String, Object?>{
    'format': 'photopod-face-result',
    'version': 1,
    'model': faceModelId,
    'analysed': DateTime.now().toUtc().toIso8601String(),
    'analyser': 'teepod',
  };
  if (answer.error != null) {
    return jsonEncode(result..['failed'] = answer.error);
  }

  final width = answer.width.toDouble();
  final height = answer.height.toDouble();
  final kept = [
    for (final face in answer.faces)
      if (face.score >= minFaceScore &&
          min(face.x2 - face.x1, face.y2 - face.y1) >= minFaceSide)
        face,
  ];
  final picture = kept.isEmpty ? null : img.decodeImage(input.picture);

  return jsonEncode(
    result
      ..['width'] = answer.width
      ..['height'] = answer.height
      ..['faces'] = [
        for (final face in kept)
          {
            'box': [
              _fraction(face.x1, width),
              _fraction(face.y1, height),
              _fraction(face.x2 - face.x1, width),
              _fraction(face.y2 - face.y1, height),
            ],
            'score': (face.score * 1000).round() / 1000,
            'embedding': encodeEmbedding(face.embedding),
            'image': picture == null
                ? null
                : _faceImage(picture, face, width, height),
          },
      ],
  );
}

double _fraction(double value, double whole) =>
    whole <= 0 ? 0 : (value / whole * 10000).round() / 10000;

/// [embedding] at unit length, as base64 of little-endian 32-bit floats,
/// which is how the faces file keeps it.

String encodeEmbedding(Float32List embedding) {
  var norm = 0.0;
  for (final v in embedding) {
    norm += v * v;
  }
  norm = sqrt(norm);
  final bytes = ByteData(embedding.length * 4);
  for (var i = 0; i < embedding.length; i++) {
    bytes.setFloat32(
      i * 4,
      norm > 0 ? embedding[i] / norm : embedding[i],
      Endian.little,
    );
  }
  return base64Encode(bytes.buffer.asUint8List());
}

// A square JPEG of [face], with room around it, cut from [picture] and
// scaled to faceImageSide, as the Pod Analyser makes it. The box is in the
// pixels TeePod measured, scaled to [picture]'s in case they differ.

String? _faceImage(
  img.Image picture,
  TeePodFace face,
  double width,
  double height,
) {
  final sx = width > 0 ? picture.width / width : 1.0;
  final sy = height > 0 ? picture.height / height : 1.0;
  final x = face.x1 * sx;
  final y = face.y1 * sy;
  final w = (face.x2 - face.x1) * sx;
  final h = (face.y2 - face.y1) * sy;
  final side = min(
    max(w, h) * faceImageMargin,
    min(picture.width, picture.height).toDouble(),
  ).toInt();
  if (side <= 0) return null;
  final left = min(max(x + w / 2 - side / 2, 0), picture.width - side).toInt();
  final top = min(max(y + h / 2 - side / 2, 0), picture.height - side).toInt();
  final crop = img.copyCrop(
    picture,
    x: left,
    y: top,
    width: side,
    height: side,
  );
  final small = img.copyResize(
    crop,
    width: faceImageSide,
    height: faceImageSide,
    interpolation: img.Interpolation.average,
  );
  return base64Encode(img.encodeJpg(small, quality: 85));
}
