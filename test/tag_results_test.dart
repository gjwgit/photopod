/// Tests for the tags the Analyser writes back, and how Tags lists them.
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

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/services/demo_library.dart';
import 'package:photopod/services/tag_results.dart';
import 'package:photopod/services/tags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // assets/demo/tags.json is what analyser/face_analyser answered for the
  // sample photos, so it doubles as a record of the service's format.

  final demo =
      jsonDecode(File('assets/demo/tags.json').readAsStringSync())
          as Map<String, dynamic>;
  final samples = demo['tags'] as Map<String, dynamic>;

  String answer({String model = tagModelId, String? failed}) => jsonEncode({
    'format': 'photopod-tag-result',
    'version': 1,
    'model': model,
    'analysed': '2026-11-11T09:00:00.000+00:00',
    if (failed == null) ...{
      'width': 1024,
      'height': 768,
      'tags': samples['grand_canyon.jpg'],
    },
    'failed': ?failed,
  });

  test('the samples are tagged by the model PhotoPod files tags by', () {
    expect(demo['model'], tagModelId);
  });

  test('reads the tags the Analyser found, best first', () {
    final read = TagResult.parse(answer())!;
    expect(read.failed, isNull);
    expect(read.tags.first.tag, 'Canyon');
    expect(read.tags.first.category, 'Nature');
    expect(read.tags.first.score, greaterThan(0.5));
  });

  test('reads why a photo could not be looked at', () {
    final read = TagResult.parse(answer(failed: 'not a picture'))!;
    expect(read.failed, 'not a picture');
    expect(read.tags, isEmpty);
  });

  test('passes over tags from another model or vocabulary', () {
    expect(TagResult.parse(answer(model: 'siglip-b16-webli:tags-v0')), isNull);
    expect(TagResult.parse('{"format": "photopod-face-result"}'), isNull);
    expect(TagResult.parse('not JSON'), isNull);
  });

  test('a tag keeps its shape through the tags file', () {
    final tags = parseFoundTags(samples['moraine_lake.jpg'] as List);
    expect(parseFoundTags(foundTagsToJson(tags)), tags);
  });

  group('PhotoTag.merge', () {
    const analyser = 'photopod:analyser';

    test('adds what the Analyser found beside the user\'s own tags', () {
      final merged = PhotoTag.merge(
        const [PhotoTag('Holiday')],
        const [PhotoTag('Beach', source: analyser, confidence: 0.9)],
        analyser,
      );
      expect(merged.map((t) => t.label), ['Holiday', 'Beach']);
      expect(merged.last.source, analyser);
      expect(merged.last.confidence, 0.9);
    });

    test('replaces what the Analyser suggested before', () {
      final merged = PhotoTag.merge(
        const [PhotoTag('Lake', source: analyser), PhotoTag('Holiday')],
        const [PhotoTag('Mountains', source: analyser)],
        analyser,
      );
      expect(merged.map((t) => t.label), ['Holiday', 'Mountains']);
    });

    test('never doubles a tag the photo already has, whatever its case', () {
      final merged = PhotoTag.merge(
        const [PhotoTag('beach'), PhotoTag('Sunset', source: 'teepod:x')],
        const [
          PhotoTag('Beach', source: analyser),
          PhotoTag('sunset', source: analyser),
        ],
        analyser,
      );
      expect(merged.map((t) => (t.label, t.source)), [
        ('beach', userSource),
        ('Sunset', 'teepod:x'),
      ]);
    });
  });

  test('Tags lists the samples by tag, the commonest first', () async {
    // Nobody is logged in, so Tags shows the samples: the secure storage
    // solidpod asks holds nothing.

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    final section = PhotoTags();
    await section.scan(DemoLibrary.items, prune: false);
    final entries = section.tagsIn(DemoLibrary.items);

    expect(entries, isNotEmpty);
    expect(entries.first.tag, anyOf('Mountains', 'Portrait'));
    for (var i = 1; i < entries.length; i++) {
      expect(
        entries[i].items.length,
        lessThanOrEqualTo(entries[i - 1].items.length),
      );
    }
    final mountains = entries.firstWhere((e) => e.tag == 'Mountains');
    expect(mountains.category, 'Nature');
    expect(
      mountains.items.map((item) => item.path),
      contains(DemoLibrary.pathOf('matterhorn.jpg')),
    );
    expect(PhotoTags.categoriesOf(entries), containsAll(['Nature', 'People']));
    section.dispose();
  });
}
