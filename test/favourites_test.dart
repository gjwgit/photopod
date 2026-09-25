/// Tests for the list of favourites held in the Pod.
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

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/models/favourites.dart';

void main() {
  group('encodeFavourites', () {
    test('writes the paths in a stable order', () {
      final json = jsonDecode(
        encodeFavourites({'photopod/data/b.jpg', 'photopod/data/a.jpg'}),
      );

      expect(json['version'], 1);
      expect(json['favourites'], [
        'photopod/data/a.jpg',
        'photopod/data/b.jpg',
      ]);
    });

    test('writes an empty list rather than nothing', () {
      final json = jsonDecode(encodeFavourites(const <String>{}));
      expect(json['favourites'], isEmpty);
    });
  });

  group('decodeFavourites', () {
    test('reads back what was written', () {
      const paths = {'photopod/data/a.jpg', 'photopod/data/holiday/b.mp4'};
      expect(decodeFavourites(encodeFavourites(paths)), paths);
    });

    test('accepts a bare list, which an earlier file might hold', () {
      expect(decodeFavourites('["photopod/data/a.jpg"]'), {
        'photopod/data/a.jpg',
      });
    });

    test('costs the user their hearts, not the album, when damaged', () {
      expect(decodeFavourites('not json at all'), isEmpty);
      expect(decodeFavourites('{"version": 1}'), isEmpty);
      expect(decodeFavourites('{"favourites": "a.jpg"}'), isEmpty);
    });

    test('drops entries that are not paths', () {
      expect(decodeFavourites('{"favourites": ["a.jpg", 7, "", null]}'), {
        'a.jpg',
      });
    });
  });
}
