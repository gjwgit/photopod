/// What PhotoPod sends TeePod and what TeePod answers, on every platform.
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

import 'dart:typed_data';

/// What TeePod is asked to do with a photo.

enum TeePodService { faces, tags }

/// One photo to look at, as an encoded JPEG or PNG, and the name its answer
/// comes back under, since answers come back as they are ready, not in the
/// order asked.

typedef TeePodImage = ({String id, Uint8List image});

/// One face TeePod found: its box in the picture's pixels, how sure the
/// detector was, and ArcFace's 512-number description of it, of unit length.

typedef TeePodFace = ({
  double x1,
  double y1,
  double x2,
  double y2,
  double score,
  Float32List embedding,
});

/// One tag from TeePod's vocabulary, and how close the picture lies to it
/// (a cosine similarity, of which only the ranking means much).

typedef TeePodTag = ({String name, double score});

/// TeePod's answer for the photo sent as [id].

class TeePodAnswer {
  const TeePodAnswer({
    required this.id,
    this.error,
    this.width = 0,
    this.height = 0,
    this.faces = const [],
    this.tags = const [],
  });

  final String id;

  /// Why TeePod could not look at the photo, or null when it could.

  final String? error;

  /// The size of the picture the face boxes are measured in.

  final int width;
  final int height;

  /// The faces found, largest first, for [TeePodService.faces].

  final List<TeePodFace> faces;

  /// The tags, best first, for [TeePodService.tags].

  final List<TeePodTag> tags;
}
