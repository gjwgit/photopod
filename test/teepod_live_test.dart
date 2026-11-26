/// Tests against the TeePod actually deployed.
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
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/constants/teepod.dart';
import 'package:photopod/services/analyser_inbox.dart';
import 'package:photopod/services/face_results.dart';
import 'package:photopod/services/tag_results.dart';
import 'package:photopod/services/teepod/attestation.dart';
import 'package:photopod/services/teepod/face_answers.dart';
import 'package:photopod/services/teepod/tag_answers.dart';
import 'package:photopod/services/teepod/teepod.dart';

// Read from the files directly: rootBundle needs the test binding, which
// would also stop every network request.

TeePodConfig _config({String? digest}) => TeePodConfig.fromJson(
  {
    ...jsonDecode(File(TeePodConfig.configAsset).readAsStringSync())
        as Map<String, dynamic>,
    'expectedImageDigest': ?digest,
  },
  clientCertPem: File(TeePodConfig.certAsset).readAsBytesSync(),
  clientKeyPem: File(TeePodConfig.keyAsset).readAsBytesSync(),
);

Future<Map<String, TeePodAnswer>> _ask(
  TeePod tee,
  TeePodService service,
  Map<String, Uint8List> photos,
) async => {
  await for (final answer in tee.analyse(
    Stream.fromIterable([
      for (final MapEntry(key: id, value: image) in photos.entries)
        (id: id, image: withoutMetadata(image)!),
    ]),
    service,
  ))
    answer.id: answer,
};

void main() {
  final skip = Platform.environment['TEEPOD_LIVE'] == '1'
      ? false
      : 'set TEEPOD_LIVE=1 to test against the deployed TeePod';

  group('the deployed TeePod', skip: skip, () {
    late TeePod tee;

    setUpAll(() async => tee = await TeePod.connect(_config()));
    tearDownAll(() async => tee.close());

    test('is refused when it is not the image expected', () async {
      await expectLater(
        TeePod.connect(_config(digest: 'sha256:${'0' * 64}')),
        throwsA(isA<AttestationError>()),
      );
    });

    test('finds the faces the Pod Analyser found, alike enough to match '
        'them', () async {
      final demo =
          jsonDecode(File('assets/demo/faces.json').readAsStringSync())
              as Map<String, dynamic>;
      final known = demo['faces'] as Map<String, dynamic>;
      const names = [
        'john_mather_2012.jpg',
        'adam_riess_2006.jpg',
        'david_wineland_2013.jpg',
      ];
      final photos = {
        for (final name in names)
          name: File('assets/demo/$name').readAsBytesSync(),
      };
      final answers = await _ask(tee, TeePodService.faces, photos);

      for (final name in names) {
        final content = faceAnswerFromTeePod((
          answer: answers[name]!,
          picture: withoutMetadata(photos[name]!)!,
        ));
        final found = FaceResult.parse(content)!.faces;
        final before = parseFoundFaces(known[name] as List);
        expect(found, hasLength(before.length), reason: name);

        var similarity = 0.0;
        for (var i = 0; i < 512; i++) {
          similarity += found.first.embedding[i] * before.first.embedding[i];
        }
        expect(similarity, greaterThan(0.9), reason: name);
        for (var i = 0; i < 4; i++) {
          expect(found.first.box[i], closeTo(before.first.box[i], 0.02));
        }
      }
    });

    test('tags the samples much as the Pod Analyser did', () async {
      const expected = {
        'great_ocean_road.jpg': 'Beach',
        'iceland_waterfall.jpg': 'Waterfall',
        'matterhorn.jpg': 'Mountains',
        'sahara.jpg': 'Desert',
        'john_mather_2016.jpg': 'Portrait',
      };
      final photos = {
        for (final name in expected.keys)
          name: File('assets/demo/$name').readAsBytesSync(),
      };
      final answers = await _ask(tee, TeePodService.tags, photos);
      for (final MapEntry(key: name, value: tag) in expected.entries) {
        final answer = TagResult.parse(tagAnswerFromTeePod(answers[name]!))!;
        expect(answer.tags.first.tag, tag, reason: name);
      }
    });
  });
}
