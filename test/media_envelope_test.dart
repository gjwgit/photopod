/// Tests for the names kept inside media files.
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
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/services/media_envelope.dart';
import 'package:photopod/services/media_names.dart';

void main() {
  final bytes = Uint8List.fromList(List.generate(300, (i) => i % 256));

  group('encodeMedia and decodeMedia', () {
    test('carry names in any script and with any punctuation', () {
      for (final name in [
        'beach.jpg',
        '海滩 照片.JPG',
        '東京タワー 夜景.png',
        '서울 야경.heic',
        'Ελλάδα — καλοκαίρι.jpg',
        'holiday #1 (50%) & "friends" + more\'s.jpg',
        'line\nbreak and {brace}.jpg',
        '🙂 emoji.gif',
      ]) {
        final media = decodeMedia(encodeMedia(name, bytes));
        expect(media.name, name);
        expect(media.bytes, bytes);
      }
    });

    test('keep the name on a line of its own before the bytes', () {
      final text = encodeMedia('海滩.jpg', bytes);
      final lines = text.split('\n');
      expect(lines, hasLength(2));
      expect(jsonDecode(lines.first), containsPair('name', '海滩.jpg'));
      expect(base64Decode(lines.last), bytes);
    });

    test('read a file from before names were kept inside it', () {
      final media = decodeMedia(base64Encode(bytes));
      expect(media.name, isNull);
      expect(media.bytes, bytes);
    });

    test('tolerate surrounding white space', () {
      final media = decodeMedia('\n ${encodeMedia('a.jpg', bytes)}\n');
      expect(media.name, 'a.jpg');
      expect(media.bytes, bytes);
    });

    test('refuse content in neither format', () {
      expect(() => decodeMedia('not base64!'), throwsFormatException);
      expect(
        () => decodeMedia('{"format":"other"}\nAAAA'),
        throwsFormatException,
      );
      expect(() => decodeMedia('{broken\nAAAA'), throwsFormatException);
      expect(
        () => decodeMedia('{"format":"photopod-media"}'),
        throwsFormatException,
      );
    });
  });

  group('isRandomStoredName', () {
    test('accepts every name randomStoredName hands out', () {
      for (final name in ['海滩.JPG', 'clip.MP4', 'no extension']) {
        expect(
          isRandomStoredName(randomStoredName(name)),
          isTrue,
          reason: name,
        );
      }
    });

    test('rejects the names files were stored under before', () {
      for (final name in [
        'WhatsApp_Image_2026-09-27_at_11.58.05.jpeg.enc.ttl',
        'PXL_20240726_211937668.jpg.enc.ttl',
        'beach.jpg',
        '3F9C0000000000000000000000000000.jpg.enc.ttl',
      ]) {
        expect(isRandomStoredName(name), isFalse, reason: name);
      }
    });
  });

  group('random folder names', () {
    test('are recognised, and the names folders had before are not', () {
      expect(isRandomFolderName(randomFolderName()), isTrue);
      for (final name in ['Holiday', 'background_pinnacles_winter_2026', '']) {
        expect(isRandomFolderName(name), isFalse, reason: name);
      }
    });

    test('give a random stored name its key', () {
      final stored = randomStoredName('海滩.jpg');
      expect(randomKeyOf(stored), stored.substring(0, 32));
      expect(randomKeyOf('PXL_20240726_211937668.jpg.enc.ttl'), isNull);
    });
  });
}
