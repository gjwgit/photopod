/// Tests for addressing items on the server.
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
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/pod_media_ops.dart';

MediaItem _file(String displayName) {
  final stored = storedNameOf(displayName);
  return MediaItem(
    name: displayName,
    rawName: stored,
    path: 'photopod/data/$stored',
    url: 'https://pod.example/photopod/data/$stored',
    isFolder: false,
    isEncrypted: true,
  );
}

MediaItem _plainFile(String name) => MediaItem(
  name: name,
  rawName: name,
  path: 'photopod/data/$name',
  url: 'https://pod.example/photopod/data/$name',
  isFolder: false,
);

MediaItem _folder(String name) => MediaItem(
  name: name,
  rawName: name,
  path: 'photopod/data/$name',
  url: 'https://pod.example/photopod/data/$name/',
  isFolder: true,
);

void main() {
  group('PodMediaOps.storedNamesOf', () {
    test('addresses an encrypted file by its name on the server', () {
      final names = PodMediaOps.storedNamesOf([_file('beach.jpg')]);

      // The display name would make the server answer 404, which the delete
      // helper counts as success — so the file would survive a delete or a
      // rename with no error reported anywhere.

      expect(names.files, ['beach.jpg.enc.ttl']);
      expect(names.files, isNot(contains('beach.jpg')));
    });

    test('keeps files and folders apart', () {
      final names = PodMediaOps.storedNamesOf([
        _file('beach.jpg'),
        _folder('holiday'),
        _file('clip.mp4'),
      ]);

      expect(names.files, ['beach.jpg.enc.ttl', 'clip.mp4.enc.ttl']);
      expect(names.folders, ['holiday']);
    });

    test('leaves a plain resource under its own name', () {
      final names = PodMediaOps.storedNamesOf([_plainFile('legacy.png')]);
      expect(names.files, ['legacy.png']);
    });

    test('a folder is named the same either way', () {
      final names = PodMediaOps.storedNamesOf([_folder('holiday')]);
      expect(names.folders, ['holiday']);
      expect(names.files, isEmpty);
    });

    test('an empty selection asks for nothing', () {
      final names = PodMediaOps.storedNamesOf([]);
      expect(names.files, isEmpty);
      expect(names.folders, isEmpty);
    });
  });
}
