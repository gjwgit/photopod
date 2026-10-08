/// Tests for the table of file names, the random names files are stored
/// under, and the names a file arriving from this device may keep.
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

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/constants/media.dart';
import 'package:photopod/services/media_names.dart';
import 'package:photopod/utils/resource_name.dart';

void main() {
  group('randomStoredName', () {
    final pattern = RegExp(r'^[0-9a-f]{32}\.jpg\.enc\.ttl$');

    test('is a long run of hex digits, the extension and the suffix', () {
      expect(randomStoredName('海滩 照片.JPG'), matches(pattern));
    });

    test('needs no escaping in a URL, whatever the original name', () {
      for (final name in ['海滩 照片.jpg', 'a#b%c.mov', 'ビーチ.png']) {
        final stored = randomStoredName(name);
        expect(Uri.encodeComponent(stored), stored, reason: name);
        expect(isSafeResourceName(stored), isTrue, reason: name);
      }
    });

    test('keeps the kind of the file', () {
      expect(
        kindOf(displayNameOf(randomStoredName('海滩.mp4'))),
        MediaKind.video,
      );
    });

    test('never draws the same name twice in practice', () {
      final names = {for (var i = 0; i < 10000; i++) randomStoredName('a.jpg')};
      expect(names, hasLength(10000));
    });
  });

  group('encodeNames and decodeNames', () {
    test('round trip names in any script', () {
      final names = {
        'photopod/data/3f9c.jpg.enc.ttl': '海滩 照片.jpg',
        'photopod/data/trip/a1b2.mov.enc.ttl': 'ビーチ.mov',
      };
      expect(decodeNames(encodeNames(names)), names);
    });

    test('yield nothing for a file that is not the expected shape', () {
      expect(decodeNames('not json'), isEmpty);
      expect(decodeNames('[1, 2]'), isEmpty);
      expect(decodeNames('{"names": {"a": 1, "b": ""}}'), isEmpty);
    });
  });

  group('safeFileName', () {
    test('keeps every script and spacing', () {
      expect(safeFileName('海滩 照片.jpg'), '海滩 照片.jpg');
      expect(safeFileName('café & co #1.jpg'), 'café & co #1.jpg');
    });

    test('replaces what a file system will not take', () {
      expect(safeFileName('a/b:c?.jpg'), 'a_b_c_.jpg');
    });

    test('never yields an empty or hidden name', () {
      expect(safeFileName('   '), 'file');
      expect(safeFileName('.jpg'), 'file.jpg');
    });
  });
}
