/// Tests for the face inbox names and the results the Analyser shares back.
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
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/models/face_book.dart';
import 'package:photopod/services/face_inbox.dart';
import 'package:photopod/services/face_results.dart';

void main() {
  group('faceKeyOf', () {
    test('is the random part of a stored name', () {
      expect(
        faceKeyOf('photopod/data/3f9c0b7a1d2e4f5a6b7c8d9e0f1a2b3c.jpg.enc.ttl'),
        '3f9c0b7a1d2e4f5a6b7c8d9e0f1a2b3c',
      );
    });

    test('is a digest of the path for a name the user gave', () {
      final key = faceKeyOf('photopod/data/Holiday/beach.jpg.enc.ttl');
      expect(key, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(key, isNot(faceKeyOf('photopod/data/Work/beach.jpg.enc.ttl')));
    });
  });

  group('FaceResult', () {
    // The faces of one sample photo, as the analyser finds them, in the
    // answer it writes beside the photo (service.py).

    final sample =
        (jsonDecode(File('assets/demo/faces.json').readAsStringSync())
                as Map<String, dynamic>)['faces']['john_mather_2012.jpg']
            as List;

    String answer({String model = faceModelId, String? failed}) => jsonEncode({
      'format': 'photopod-face-result',
      'version': 1,
      'model': model,
      'analysed': '2026-11-10T09:00:00.000+00:00',
      if (failed == null) ...{'width': 1054, 'height': 1280, 'faces': sample},
      'failed': ?failed,
    });

    test('reads the faces the Analyser found', () {
      final read = FaceResult.parse(answer())!;
      expect(read.failed, isNull);
      expect(read.faces, hasLength(1));
      expect(read.faces.single.embedding, hasLength(512));
    });

    test('reads why a photo could not be looked at', () {
      final read = FaceResult.parse(answer(failed: 'not a picture'))!;
      expect(read.failed, 'not a picture');
      expect(read.faces, isEmpty);
    });

    test('ignores answers made with other models, or not answers at all', () {
      expect(FaceResult.parse(answer(model: 'other')), isNull);
      expect(FaceResult.parse('{"format": "something else"}'), isNull);
      expect(FaceResult.parse('not JSON'), isNull);
    });
  });
}
