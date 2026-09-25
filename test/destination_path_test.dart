/// Tests for the destination path rule.
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

import 'package:photopod/utils/destination_path.dart';

const _root = 'photopod/data';

void main() {
  group('resolveDestination as a folder', () {
    test('an empty path means the album root', () {
      expect(resolveDestination(_root, '')?.folderPath, _root);
      expect(resolveDestination(_root, '   ')?.folderPath, _root);
      expect(resolveDestination(_root, '/')?.folderPath, _root);
      expect(resolveDestination(_root, '')?.renames, isFalse);
    });

    test('a folder name is resolved inside the root', () {
      expect(
        resolveDestination(_root, 'holiday')?.folderPath,
        '$_root/holiday',
      );
      expect(
        resolveDestination(_root, 'holiday/2026')?.folderPath,
        '$_root/holiday/2026',
      );
    });

    test('stray separators are ignored', () {
      expect(
        resolveDestination(_root, '/holiday/')?.folderPath,
        '$_root/holiday',
      );
      expect(
        resolveDestination(_root, 'holiday//2026')?.folderPath,
        '$_root/holiday/2026',
      );
    });

    test('the root pasted back in is not repeated', () {
      expect(resolveDestination(_root, _root)?.folderPath, _root);
      expect(
        resolveDestination(_root, '$_root/holiday')?.folderPath,
        '$_root/holiday',
      );
    });

    test('a folder name with a space is tidied rather than escaped', () {
      // A percent-escaped name loses its encryption key, because solidpod
      // decodes the escapes when it works out where to file the key and does
      // not put them back when it looks the key up again.

      expect(
        resolveDestination(_root, 'Family Holiday')?.folderPath,
        '$_root/Family_Holiday',
      );
    });

    test('a dot in a folder name is not an extension', () {
      final destination = resolveDestination(_root, 'holiday.2026');
      expect(destination?.folderPath, '$_root/holiday.2026');
      expect(destination?.renames, isFalse);
    });
  });

  group('resolveDestination with a new file name', () {
    test('a media extension names the file, not a folder', () {
      final destination = resolveDestination(_root, 'holiday/sunset.jpg');
      expect(destination?.folderPath, '$_root/holiday');
      expect(destination?.newName, 'sunset.jpg');
      expect(destination?.renames, isTrue);
    });

    test('a bare file name keeps the item in the album root', () {
      final destination = resolveDestination(_root, '013.png');
      expect(destination?.folderPath, _root);
      expect(destination?.newName, '013.png');
    });

    test('the full path of a file is read the same way', () {
      final destination = resolveDestination(_root, '$_root/013.png');
      expect(destination?.folderPath, _root);
      expect(destination?.newName, '013.png');
    });

    test('every supported format is recognised as a name', () {
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
        expect(resolveDestination(_root, name)?.newName, name, reason: name);
      }
    });

    test('an unknown extension is taken as a folder', () {
      final destination = resolveDestination(_root, 'notes.txt');
      expect(destination?.folderPath, '$_root/notes.txt');
      expect(destination?.renames, isFalse);
    });

    test('a trailing slash insists it is a folder', () {
      final destination = resolveDestination(_root, 'sunset.jpg/');
      expect(destination?.folderPath, '$_root/sunset.jpg');
      expect(destination?.renames, isFalse);
    });

    test('the folder is tidied while the new name is left as typed', () {
      // The folder part goes straight into a URL, so it is reduced to
      // characters that need no escaping. The name is reported as typed and
      // is checked by the dialogue, which refuses a space rather than
      // silently renaming what the user has just written.

      final destination = resolveDestination(_root, 'My Trip/sun set.jpg');
      expect(destination?.folderPath, '$_root/My_Trip');
      expect(destination?.newName, 'sun set.jpg');
    });
  });

  group('resolveDestination refusals', () {
    test('refuses to climb out of the album', () {
      for (final typed in [
        '..',
        '../',
        '../profile',
        '../../',
        'holiday/../..',
        '$_root/../../profile',
      ]) {
        expect(resolveDestination(_root, typed), isNull, reason: typed);
      }
    });

    test('refuses a bare current-directory segment', () {
      expect(resolveDestination(_root, '.'), isNull);
      expect(resolveDestination(_root, 'holiday/./2026'), isNull);
    });

    test('a folder that merely starts with dots is still fine', () {
      expect(resolveDestination(_root, '...odd')?.folderPath, '$_root/...odd');
      expect(resolveDestination(_root, '..odd')?.folderPath, '$_root/..odd');
    });
  });
}
