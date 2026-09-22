/// Tests for resource name validation.
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

import 'package:photopod/utils/name_validator.dart';

void main() {
  group('validateName for files', () {
    test('accepts a plain photo name', () {
      expect(validateName('beach.jpg', isFolder: false), isNull);
    });

    test('accepts every supported extension', () {
      for (final name in [
        'a.jpg',
        'a.jpeg',
        'a.png',
        'a.gif',
        'a.tiff',
        'a.tif',
        'a.mp4',
        'a.mov',
      ]) {
        expect(validateName(name, isFolder: false), isNull, reason: name);
      }
    });

    test('is not fussy about the case of the extension', () {
      expect(validateName('BEACH.JPG', isFolder: false), isNull);
    });

    test('rejects an empty name', () {
      expect(validateName('  ', isFolder: false), isNotNull);
    });

    test('rejects a name longer than the limit', () {
      final name = '${'a' * maxNameLength}.jpg';
      expect(validateName(name, isFolder: false), isNotNull);
    });

    test('rejects characters that would break the URL', () {
      for (final name in [
        'a/b.jpg',
        r'a\b.jpg',
        'a?b.jpg',
        'a#b.jpg',
        'a%b.jpg',
        'a*b.jpg',
        'a:b.jpg',
        'a"b.jpg',
        'a<b.jpg',
        'a>b.jpg',
        'a|b.jpg',
      ]) {
        expect(validateName(name, isFolder: false), isNotNull, reason: name);
      }
    });

    test('rejects a name with no usable extension', () {
      expect(validateName('notes.txt', isFolder: false), isNotNull);
      expect(validateName('beach', isFolder: false), isNotNull);
    });

    test('rejects leading and trailing spaces', () {
      expect(validateName(' beach.jpg', isFolder: false), isNotNull);
      expect(validateName('beach.jpg ', isFolder: false), isNotNull);
    });

    test('rejects a hidden name', () {
      expect(validateName('.beach.jpg', isFolder: false), isNotNull);
    });

    test('refuses to turn a photo into a video', () {
      expect(
        validateName('beach.mp4', isFolder: false, originalName: 'beach.jpg'),
        isNotNull,
      );
    });

    test('allows a change between two photo formats', () {
      expect(
        validateName('beach.png', isFolder: false, originalName: 'beach.jpg'),
        isNull,
      );
    });
  });

  group('validateName for folders', () {
    test('accepts a name with no extension', () {
      expect(validateName('Holiday 2026', isFolder: true), isNull);
    });

    test('rejects the special directory names', () {
      expect(validateName('.', isFolder: true), isNotNull);
      expect(validateName('..', isFolder: true), isNotNull);
    });

    test('rejects a separator in the name', () {
      expect(validateName('a/b', isFolder: true), isNotNull);
    });
  });
}
