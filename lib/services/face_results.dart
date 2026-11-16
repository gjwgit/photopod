/// What the Analyser writes back into the face inbox: the faces in a photo.
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

import 'package:flutter/foundation.dart';

import 'package:photopod/models/face_book.dart';

/// What the Analyser found in one photo left in the face inbox, read from
/// the `<key>.faces.enc.ttl` it wrote beside the photo:
///
///     {"format": "photopod-face-result", "version": 1, "model": ...,
///      "analysed": ..., "width": w, "height": h, "faces": [...]}
///
/// or, for a photo it could not read, `"failed": "<why>"` in place of the
/// faces. See analyser/face_analyser/face_analyser/service.py.

class FaceResult {
  /// The faces found, empty when there are none or the photo [failed].

  final List<FoundFace> faces;

  /// Why the photo could not be read, or null when it was.

  final String? failed;

  const FaceResult(this.faces, [this.failed]);

  /// The result [content] holds, or null when it is not one, or was made
  /// with other models, whose embeddings mean nothing to the faces already
  /// found. Such a photo is simply looked at again.

  static FaceResult? parse(String content) {
    try {
      final json = jsonDecode(content);
      if (json is! Map<String, dynamic>) return null;
      if (json['format'] != 'photopod-face-result') return null;
      if (json['model'] != faceModelId) return null;
      final failed = json['failed'];
      if (failed != null) return FaceResult(const [], '$failed');
      return FaceResult(parseFoundFaces(json['faces'] as List? ?? const []));
    } on Object catch (e) {
      debugPrint('PhotoPod: not a face result: $e');
      return null;
    }
  }
}

/// The faces in [faces], as the Analyser lists them: `box` as fractions of
/// the photo's size, `score`, `embedding` as base64 of little-endian
/// float32, and `image` as a base64 JPEG.

List<FoundFace> parseFoundFaces(List<dynamic> faces) => [
  for (final face in faces.cast<Map<String, dynamic>>())
    (
      box: [for (final v in face['box'] as List) (v as num).toDouble()],
      score: (face['score'] as num).toDouble(),
      embedding: Float32List.view(
        Uint8List.fromList(base64Decode(face['embedding'] as String)).buffer,
      ),
      image: face['image'] == null
          ? null
          : base64Decode(face['image'] as String),
    ),
];
