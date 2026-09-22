/// Tests for size and date formatting.
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

import 'package:photopod/utils/formatting.dart';

void main() {
  group('formatBytes', () {
    test('shows bytes below a kilobyte', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(999), '999 B');
    });

    test('steps up through the units', () {
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });

    test('drops the decimal once the number is large', () {
      expect(formatBytes(200 * 1024), '200 KB');
    });

    test('shows nothing at all for an unknown size', () {
      expect(formatBytes(null), '');
    });
  });

  group('formatDateTime', () {
    test('renders a local time in a sortable form', () {
      final when = DateTime(2026, 9, 22, 14, 5);
      expect(formatDateTime(when), '2026-09-22 14:05');
    });

    test('pads single digit parts', () {
      final when = DateTime(2026, 1, 2, 3, 4);
      expect(formatDateTime(when), '2026-01-02 03:04');
    });

    test('marks an unknown date rather than inventing one', () {
      expect(formatDateTime(null), '—');
    });
  });
}
