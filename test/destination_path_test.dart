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
  group('resolveDestination', () {
    test('an empty path means the album root', () {
      expect(resolveDestination(_root, ''), _root);
      expect(resolveDestination(_root, '   '), _root);
      expect(resolveDestination(_root, '/'), _root);
    });

    test('a folder name is resolved inside the root', () {
      expect(resolveDestination(_root, 'holiday'), '$_root/holiday');
      expect(resolveDestination(_root, 'holiday/2026'), '$_root/holiday/2026');
    });

    test('stray separators are ignored', () {
      expect(resolveDestination(_root, '/holiday/'), '$_root/holiday');
      expect(resolveDestination(_root, 'holiday//2026'), '$_root/holiday/2026');
    });

    test('the root pasted back in is not repeated', () {
      expect(resolveDestination(_root, _root), _root);
      expect(resolveDestination(_root, '$_root/holiday'), '$_root/holiday');
    });

    test('a folder name with a space is encoded for the URL', () {
      expect(
        resolveDestination(_root, 'Family Holiday'),
        '$_root/Family%20Holiday',
      );
    });

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
      expect(resolveDestination(_root, '...odd'), '$_root/...odd');
      expect(resolveDestination(_root, '..odd'), '$_root/..odd');
    });
  });
}
