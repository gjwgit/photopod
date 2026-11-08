/// Tests for the catalog of everything known about the user's photos.
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

import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/models/photo_metadata.dart';
import 'package:photopod/services/media_catalog.dart';
import 'package:photopod/services/media_names.dart';

const String _key = '3f9c0000000000000000000000000000';
const String _folder = 'a1b20000000000000000000000000000';

void main() {
  group('catalogKeyOf', () {
    test('is the random part of a stored file name', () {
      expect(catalogKeyOf('photopod/data/$_folder/$_key.jpg.enc.ttl'), _key);
    });

    test('stays the same wherever the file is moved', () {
      expect(
        catalogKeyOf('photopod/data/$_key.jpg.enc.ttl'),
        catalogKeyOf('photopod/data/$_folder/$_key.jpg.enc.ttl'),
      );
    });

    test('is the random name of a folder', () {
      expect(catalogKeyOf('photopod/data/$_folder'), _folder);
    });

    test('is the path of anything stored under its own name', () {
      expect(
        catalogKeyOf('photopod/data/beach.jpg.enc.ttl'),
        'photopod/data/beach.jpg.enc.ttl',
      );
    });
  });

  group('encodeCatalog and decodeCatalog', () {
    test('round trip everything an entry holds', () {
      final entries = {
        _key: const CatalogEntry(
          'photopod/data/$_key.jpg.enc.ttl',
          name: '海滩 照片.jpg',
          taken: '2025-04-05T09:10:00.000',
          metadata: PhotoMetadata(
            width: 4032,
            latitude: -33.8,
            longitude: 151.2,
          ),
          tags: [
            PhotoTag('beach'),
            PhotoTag('ocean', source: 'teepod:vision', confidence: 0.93),
          ],
          faces: [
            PhotoFace('Alice', box: [0.31, 0.22, 0.12, 0.16]),
            PhotoFace('Bob'),
          ],
        ),
      };
      final text = encodeCatalog(entries);
      expect(encodeCatalog(decodeCatalog(text)), text);

      final entry = decodeCatalog(text)[_key]!;
      expect(entry.name, '海滩 照片.jpg');
      expect(entry.metadata!.hasLocation, isTrue);
      expect(entry.tags.last.source, 'teepod:vision');
      expect(entry.tags.last.confidence, 0.93);
      expect(entry.faces.first.box, [0.31, 0.22, 0.12, 0.16]);
      expect(entry.faces.last.box, isNull);
    });

    test('always produce the same bytes for the same catalog', () {
      const a = CatalogEntry('photopod/data/a', name: 'a');
      const b = CatalogEntry('photopod/data/b', name: 'b');
      expect(encodeCatalog({'b': b, 'a': a}), encodeCatalog({'a': a, 'b': b}));
    });

    test('yield nothing for a file that is not the expected shape', () {
      expect(decodeCatalog('not json'), isEmpty);
      expect(decodeCatalog('[1, 2]'), isEmpty);
      expect(decodeCatalog('{"items": [1]}'), isEmpty);
    });

    test('drop an entry with no path and keep the rest', () {
      final decoded = decodeCatalog(
        '{"items": {"a": {"name": "x"}, "b": {"path": "p/b", "name": "y"}}}',
      );
      expect(decoded.keys, ['b']);
    });

    test('drop the parts of an entry that are the wrong shape', () {
      final entry = decodeCatalog(
        '{"items": {"a": {"path": "p/a", "taken": "yesterday", '
        '"tags": [{"label": ""}, 3, {"label": "sea"}], '
        '"faces": [{"name": "Ann", "box": [0.1, 2, 0.1, 0.1]}]}}}',
      )['a']!;
      expect(entry.taken, isNull);
      expect(entry.tags.single.label, 'sea');
      expect(entry.tags.single.source, userSource);
      expect(entry.faces.single.name, 'Ann');
      expect(entry.faces.single.box, isNull);
    });
  });

  group('catalogFromNames', () {
    test('takes every name and date in the table of names', () {
      const photo = 'photopod/data/$_folder/$_key.jpg.enc.ttl';
      const folder = 'photopod/data/$_folder';
      const old = 'photopod/data/old.jpg.enc.ttl';
      final text = encodeNames(
        {photo: 'beach.jpg', folder: 'Holiday'},
        {photo: encodeDate(DateTime(2025, 4, 5, 9, 10)), old: '2020-01-01'},
      );

      final catalog = catalogFromNames(text);
      expect(catalog, hasLength(3));
      expect(catalog[_key]!.path, photo);
      expect(catalog[_key]!.name, 'beach.jpg');
      expect(catalog[_key]!.taken, '2025-04-05T09:10:00.000');
      expect(catalog[_folder]!.name, 'Holiday');
      expect(catalog[old]!.name, isNull);
      expect(catalog[old]!.taken, '2020-01-01');
    });

    test('is empty for a table that cannot be read', () {
      expect(catalogFromNames('not json'), isEmpty);
    });
  });

  group('PhotoTitle.merge', () {
    const mine = PhotoTitle('Our beach');
    const suggested = PhotoTitle('A beach', source: 'teepod:vision');

    test('takes a title where there was none', () {
      expect(PhotoTitle.merge(null, mine)?.text, 'Our beach');
      expect(PhotoTitle.merge(null, suggested)?.source, 'teepod:vision');
    });

    test('lets the user replace a suggestion, which becomes theirs', () {
      final merged = PhotoTitle.merge(suggested, const PhotoTitle('Bondi'));
      expect(merged?.text, 'Bondi');
      expect(merged?.isUsers, isTrue);
    });

    test('never lets a suggestion replace the user\'s title', () {
      expect(PhotoTitle.merge(mine, suggested), same(mine));
    });

    test('lets a newer suggestion replace an older one', () {
      final newer = PhotoTitle.merge(
        suggested,
        const PhotoTitle('Sunset at the beach', source: 'teepod:vision2'),
      );
      expect(newer?.text, 'Sunset at the beach');
      expect(newer?.source, 'teepod:vision2');
    });

    test('takes the title away when the user empties it', () {
      expect(PhotoTitle.merge(mine, const PhotoTitle('  ')), isNull);
      expect(PhotoTitle.merge(suggested, const PhotoTitle('')), isNull);
    });

    test('changes nothing for an empty suggestion', () {
      expect(
        PhotoTitle.merge(suggested, const PhotoTitle('', source: 'teepod:x')),
        same(suggested),
      );
    });

    test('trims what it is given', () {
      expect(
        PhotoTitle.merge(null, const PhotoTitle('  Bondi '))?.text,
        'Bondi',
      );
    });
  });

  group('the title in the catalog', () {
    test('round trips with its source', () {
      final entries = {
        _key: const CatalogEntry(
          'photopod/data/x',
          title: PhotoTitle('A beach', source: 'teepod:vision'),
        ),
      };
      final title = decodeCatalog(encodeCatalog(entries))[_key]!.title!;
      expect(title.text, 'A beach');
      expect(title.source, 'teepod:vision');
    });

    test('is the user\'s when written by hand as plain text', () {
      final entry = decodeCatalog(
        '{"items": {"a": {"path": "p/a", "title": "Bondi"}}}',
      )['a']!;
      expect(entry.title?.text, 'Bondi');
      expect(entry.title?.isUsers, isTrue);
    });

    test('is left out when empty or the wrong shape', () {
      final entries = decodeCatalog(
        '{"items": {"a": {"path": "p/a", "title": ""}, '
        '"b": {"path": "p/b", "title": 3}}}',
      );
      expect(entries['a']!.title, isNull);
      expect(entries['b']!.title, isNull);
    });

    test('is kept when other fields change, and can be taken away', () {
      const entry = CatalogEntry('p/a', title: PhotoTitle('Bondi'));
      expect(entry.copyWith(name: 'b.jpg').title?.text, 'Bondi');
      expect(entry.withTitle(null).title, isNull);
    });
  });
}
