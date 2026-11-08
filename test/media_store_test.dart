/// Tests for where photos are stored, and the albums folders become.
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
/// Authors: Graham Williams

library;

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/models/albums.dart';
import 'package:photopod/services/media_catalog.dart';
import 'package:photopod/services/media_names.dart';
import 'package:photopod/services/media_store.dart';
import 'package:photopod/services/store_migration.dart';

const String _root = 'photopod/data';

void main() {
  group('storePathOf', () {
    test('files a photo by the first digit of its random name', () {
      expect(
        storePathOf(_root, '3f9c0000000000000000000000000000.jpg.enc.ttl'),
        '$_root/media/3/3f9c0000000000000000000000000000.jpg.enc.ttl',
      );
    });

    test('has a folder for every digit a random name can start with', () {
      for (var i = 0; i < 200; i++) {
        final stored = randomStoredName('a.jpg');
        final shard = storePathOf(_root, stored).split('/')[3];
        expect(storeShards, contains(shard), reason: stored);
      }
    });

    test('keeps the catalog key a photo had in its folder', () {
      const stored = '3f9c0000000000000000000000000000.jpg.enc.ttl';
      expect(
        catalogKeyOf(storePathOf(_root, stored)),
        catalogKeyOf('$_root/a1b20000000000000000000000000000/$stored'),
      );
    });
  });

  group('albumNameForFolder', () {
    test('is the name of a folder at the top of the album', () {
      expect(albumNameForFolder(['Holiday']), 'Holiday');
    });

    test('takes the names of the folders a folder is inside', () {
      expect(albumNameForFolder(['Holiday', 'Beach']), 'Holiday › Beach');
    });

    test('is always a name an album may have', () {
      expect(validateAlbumName(albumNameForFolder(['海滩', 'ビーチ'])), isNull);
    });
  });
}
