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
import 'package:photopod/services/face_engine.dart';
import 'package:photopod/services/face_inbox.dart';

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

  group('FaceAnalyserResults', () {
    // The faces of one sample photo, as the analyser finds them, in the
    // results document it publishes (service.py).

    final sample =
        (jsonDecode(File('assets/demo/faces.json').readAsStringSync())
                as Map<String, dynamic>)['faces']['john_mather_2012.jpg']
            as List;

    Map<String, dynamic> results({String model = faceModelId}) => {
      'format': 'photopod-face-results',
      'version': 1,
      'model': model,
      'generated': '2026-11-10T09:00:00.000+00:00',
      'items': {
        'a' * 32: {'width': 1054, 'height': 1280, 'faces': sample},
        'b' * 32: {'width': 800, 'height': 600, 'faces': <dynamic>[]},
      },
      'failed': {'c' * 32: 'The upload is not a picture OpenCV can read.'},
    };

    test('reads the faces of each photo and the photos that failed', () {
      final read = FaceAnalyserResults.fromJson(results());
      expect(read.faces['a' * 32], hasLength(1));
      expect(read.faces['a' * 32]!.single.embedding, hasLength(128));
      expect(read.faces['b' * 32], isEmpty);
      expect(read.failed.keys, ['c' * 32]);
      expect(read.keys, {'a' * 32, 'b' * 32, 'c' * 32});
    });

    test('ignores results made with other models', () {
      expect(
        FaceAnalyserResults.fromJson(results(model: 'other')).isEmpty,
        isTrue,
      );
    });
  });

  test('a run report is read as the analyser writes it', () {
    final run = FaceAnalyserRun.fromJson({
      'result_url': 'https://server/Analyser/photopod/data/faces/x.enc.ttl',
      'analysed': 3,
      'failed': 1,
      'pending': 5,
      'waiting': 4,
    });
    expect(run.resultUrl, endsWith('x.enc.ttl'));
    expect((run.analysed, run.failed, run.pending, run.waiting), (3, 1, 5, 4));
  });
}
