/// Tests for recognising duplicates and merging what is known about them.
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

import 'package:photopod/dialogs/duplicate_dialog.dart';
import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/models/photo_metadata.dart';
import 'package:photopod/services/media_catalog.dart';
import 'package:photopod/services/media_duplicates.dart';

final String _hash = contentHashOf(Uint8List.fromList(utf8.encode('photo')));
final String _other = contentHashOf(Uint8List.fromList(utf8.encode('other')));

String _path(String key, [String extension = 'jpg']) =>
    'photopod/data/media/${key[0]}/$key.$extension.enc.ttl';

final String _a = _path('a${'0' * 31}');
final String _b = _path('b${'0' * 31}');
final String _c = _path('c${'0' * 31}');
final String _d = _path('d${'0' * 31}', 'mp4');

void main() {
  group('contentHashOf', () {
    test('is the SHA-256 digest in lower-case hexadecimal', () {
      expect(
        contentHashOf(Uint8List.fromList(utf8.encode('abc'))),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(isContentHash(_hash), isTrue);
    });

    test('hashContent agrees for small and large files', () async {
      final small = Uint8List.fromList([1, 2, 3]);
      final large = Uint8List(2 << 20);
      expect(await hashContent(small), contentHashOf(small));
      expect(await hashContent(large), contentHashOf(large));
    });
  });

  group('CatalogEntry hash', () {
    test('survives the catalog', () {
      final entries = {'a': CatalogEntry(_a, name: 'beach.jpg', hash: _hash)};
      final back = decodeCatalog(encodeCatalog(entries));
      expect(back['a']!.hash, _hash);
    });

    test('is dropped when it is not a digest', () {
      final entry = CatalogEntry.fromJson({'path': _a, 'sha256': 'nonsense'});
      expect(entry!.hash, isNull);
    });

    test('is kept by withTitle, withPlace and copyWith', () {
      final entry = CatalogEntry(_a, hash: _hash);
      expect(entry.withTitle(const PhotoTitle('Sunset')).hash, _hash);
      expect(entry.withPlace(null).hash, _hash);
      expect(entry.copyWith(name: 'x.jpg').hash, _hash);
    });
  });

  group('CatalogEntry.merge', () {
    test('keeps what the photo in the Pod says and fills in the rest', () {
      final kept = CatalogEntry(
        _a,
        name: 'beach.jpg',
        metadata: const PhotoMetadata(width: 4000, height: 3000),
        tags: const [PhotoTag('Beach')],
        faces: const [PhotoFace('Ann')],
      );
      final other = CatalogEntry(
        '',
        name: 'IMG_0001.JPG',
        metadata: const PhotoMetadata(
          width: 1,
          height: 1,
          cameraMake: 'Apple',
          latitude: -35.3,
          longitude: 149.1,
        ),
        tags: const [PhotoTag('beach'), PhotoTag('sea')],
        faces: const [PhotoFace('ann'), PhotoFace('Bob')],
        hash: _hash,
      );
      final merged = CatalogEntry.merge(kept, other);
      expect(merged.path, _a);
      expect(merged.name, 'beach.jpg');
      expect(merged.metadata!.width, 4000);
      expect(merged.metadata!.cameraMake, 'Apple');
      expect(merged.metadata!.latitude, -35.3);
      expect(merged.tags.map((t) => t.label), ['Beach', 'sea']);
      expect(merged.faces.map((f) => f.name), ['Ann', 'Bob']);
      expect(merged.hash, _hash);
    });

    test('prefers the date the camera recorded', () {
      final kept = CatalogEntry(_a, taken: '2026-01-02T00:00:00.000Z');
      final shutter = DateTime.utc(2020, 5, 6, 7, 8, 9);
      final other = CatalogEntry(
        '',
        taken: shutter.toIso8601String(),
        metadata: PhotoMetadata(taken: shutter),
      );
      expect(DateTime.parse(CatalogEntry.merge(kept, other).taken!), shutter);
    });

    test('takes the earlier date when neither has the camera\'s', () {
      final kept = CatalogEntry(_a, taken: '2026-01-02T00:00:00.000Z');
      final other = const CatalogEntry('', taken: '2025-01-02T00:00:00.000Z');
      expect(CatalogEntry.merge(kept, other).taken, other.taken);
      expect(CatalogEntry.merge(other, kept).taken, other.taken);
    });

    test('a title the user gave beats a suggestion', () {
      final kept = CatalogEntry(
        _a,
        title: const PhotoTitle('Waves', source: 'teepod:vision'),
      );
      final other = const CatalogEntry('', title: PhotoTitle('Our holiday'));
      expect(CatalogEntry.merge(kept, other).title!.text, 'Our holiday');
      expect(CatalogEntry.merge(other, kept).title!.text, 'Our holiday');
    });
  });

  group('PhotoMetadata.merged', () {
    test('never pairs a latitude with the other copy\'s longitude', () {
      const kept = PhotoMetadata(latitude: 10);
      const other = PhotoMetadata(latitude: 20, longitude: 30);
      final merged = PhotoMetadata.merged(kept, other)!;
      expect((merged.latitude, merged.longitude), (20.0, 30.0));
    });

    test('is whichever there is when only one is known', () {
      const one = PhotoMetadata(iso: 100);
      expect(PhotoMetadata.merged(null, one), same(one));
      expect(PhotoMetadata.merged(null, null), isNull);
    });
  });

  group('duplicateCandidates', () {
    final taken = DateTime.utc(2024, 3, 4, 5, 6, 7);
    final entries = [
      CatalogEntry(_a, name: 'beach.jpg', hash: _hash),
      CatalogEntry(_b, name: 'IMG_1.jpg', taken: taken.toIso8601String()),
      CatalogEntry(_c, name: 'Beach.JPG'),
      CatalogEntry(_d, name: 'beach.mp4', taken: taken.toIso8601String()),
      CatalogEntry(_path('e${'0' * 31}'), name: 'beach.jpg', hash: _other),
    ];

    test('finds the known copy and the likely ones', () {
      final found = duplicateCandidates(
        entries,
        hash: _hash,
        name: 'beach.jpg',
        taken: taken,
      );
      expect(found.known.map((e) => e.path), [_a]);

      // The same moment first, then the same name; never a video for a
      // photo, nor one whose different digest is already known.

      expect(found.possible.map((e) => e.path), [_b, _c]);
    });

    test('is limited', () {
      final found = duplicateCandidates(
        entries,
        hash: _hash,
        name: 'beach.jpg',
        taken: taken,
        limit: 1,
      );
      expect(found.possible.map((e) => e.path), [_b]);
    });
  });

  group('duplicateRows', () {
    test('compares both copies and leaves out what neither has', () {
      final inPod = CatalogEntry(_a, name: 'beach.jpg');
      final incoming = const CatalogEntry(
        '',
        name: 'IMG_0001.JPG',
        metadata: PhotoMetadata(cameraMake: 'Apple'),
      );
      final rows = duplicateRows(
        inPod,
        incoming,
        CatalogEntry.merge(inPod, incoming),
        favourite: true,
        albums: const ['Holiday'],
      );
      expect(rows.map((r) => r.label), [
        'Name',
        'Camera',
        'Favourite',
        'Albums',
      ]);
      final camera = rows[1];
      expect(
        (camera.inPod, camera.incoming, camera.merged),
        ('', 'Apple', 'Apple'),
      );
    });
  });
}
