/// Tests for the album files and album names.
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

import 'package:photopod/models/albums.dart';

void main() {
  group('encodeAlbum', () {
    test('writes the paths in a stable order', () {
      final json = jsonDecode(
        encodeAlbum({'photopod/data/b.jpg', 'photopod/data/a.jpg'}),
      );

      expect(json['version'], 1);
      expect(json['items'], ['photopod/data/a.jpg', 'photopod/data/b.jpg']);
    });

    test('writes an empty list for a new album', () {
      expect(jsonDecode(encodeAlbum(const <String>{}))['items'], isEmpty);
    });
  });

  group('decodeAlbum', () {
    test('reads back what was written', () {
      const paths = {'photopod/data/a.jpg', 'photopod/data/holiday/b.mp4'};
      expect(decodeAlbum(encodeAlbum(paths)), paths);
    });

    test('accepts a bare list', () {
      expect(decodeAlbum('["photopod/data/a.jpg"]'), {'photopod/data/a.jpg'});
    });

    test('an empty album rather than an error when damaged', () {
      expect(decodeAlbum('not json at all'), isEmpty);
      expect(decodeAlbum('{"version": 1}'), isEmpty);
      expect(decodeAlbum('{"items": ["a.jpg", 7, "", null]}'), {'a.jpg'});
    });
  });

  group('validateAlbumName', () {
    test('accepts an ordinary name', () {
      expect(validateAlbumName('Holiday_2026'), isNull);
    });

    test('refuses Favourites in any case', () {
      expect(validateAlbumName('Favourites'), isNotNull);
      expect(validateAlbumName('favourites'), isNotNull);
    });

    test('refuses a name already taken, ignoring case', () {
      expect(validateAlbumName('holiday', existing: ['Holiday']), isNotNull);
    });

    test('lets an album being renamed keep its own name in a new case', () {
      expect(
        validateAlbumName('HOLIDAY', existing: ['Holiday'], current: 'Holiday'),
        isNull,
      );
    });

    test('follows the rules for a resource name', () {
      expect(validateAlbumName(''), isNotNull);
      expect(validateAlbumName('Summer holiday'), isNotNull);
      expect(validateAlbumName('.hidden'), isNotNull);
    });
  });

  group('albumNameOfFile', () {
    test('reads the name of an encrypted album file', () {
      expect(albumNameOfFile('Holiday.json.enc.ttl'), 'Holiday');
    });

    test('still reads an album an earlier build left as plain JSON', () {
      expect(albumNameOfFile('Holiday.json'), 'Holiday');
    });

    test('passes over anything that is not an album file', () {
      expect(albumNameOfFile('notes.txt'), isNull);
      expect(albumNameOfFile('.json.enc.ttl'), isNull);
    });
  });
}
