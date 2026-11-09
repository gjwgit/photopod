/// Tests for the filter bar's search.
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
import 'package:photopod/models/media_filter.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/photo_metadata.dart';

MediaItem _item(String name, {DateTime? taken}) => MediaItem(
  name: name,
  rawName: name,
  path: 'photopod/data/$name',
  url: 'https://pod.example/photopod/data/$name',
  isFolder: false,
  taken: taken,
);

final _beach = _item('IMG_0001.jpg', taken: DateTime(2026, 10, 17, 9));
final _beachEntry = CatalogEntry(
  _beach.path,
  title: const PhotoTitle('Sunset over the harbour'),
  metadata: const PhotoMetadata(latitude: -35.28, longitude: 149.13),
  tags: const [
    PhotoTag('beach'),
    PhotoTag('sunset', source: 'teepod:x'),
  ],
  faces: const [PhotoFace('Jane Doe')],
);

final _office = _item('report.png', taken: DateTime(2025, 3, 2));
final _officeEntry = CatalogEntry(_office.path, tags: const [PhotoTag('work')]);

bool _matches(String text, MediaItem item, CatalogEntry? entry) =>
    MediaSearch.parse(text).matches(item, entry);

void main() {
  test('an empty search matches everything', () {
    final search = MediaSearch.parse('   ');
    expect(search.isEmpty, isTrue);
    expect(search.matches(_office, null), isTrue);
  });

  test('a keyword looks in the name, title, tags and people', () {
    expect(_matches('img_0001', _beach, _beachEntry), isTrue);
    expect(_matches('HARBOUR', _beach, _beachEntry), isTrue);
    expect(_matches('sunset', _beach, _beachEntry), isTrue);
    expect(_matches('jane', _beach, _beachEntry), isTrue);
    expect(_matches('harbour', _office, _officeEntry), isFalse);
  });

  test('every term must match', () {
    expect(_matches('beach jane', _beach, _beachEntry), isTrue);
    expect(_matches('beach work', _beach, _beachEntry), isFalse);
  });

  test('fields look only where they say', () {
    expect(_matches('person:jane', _beach, _beachEntry), isTrue);
    expect(_matches('person:"Jane Doe"', _beach, _beachEntry), isTrue);
    expect(_matches('person:beach', _beach, _beachEntry), isFalse);
    expect(_matches('tag:beach', _beach, _beachEntry), isTrue);
    expect(_matches('tag:jane', _beach, _beachEntry), isFalse);
    expect(_matches('title:harbour', _beach, _beachEntry), isTrue);
    expect(_matches('title:', _office, _officeEntry), isFalse);
    expect(_matches('name:report', _office, _officeEntry), isTrue);
    expect(_matches('tag:', _office, null), isFalse);
  });

  test('a minus leaves out what a term matches', () {
    expect(_matches('-tag:work', _beach, _beachEntry), isTrue);
    expect(_matches('-tag:work', _office, _officeEntry), isFalse);
  });

  test('an unknown prefix is searched for as it stands', () {
    final search = MediaSearch.parse('foo:bar');
    expect(search.terms.single.field, SearchField.keyword);
    expect(search.terms.single.value, 'foo:bar');
  });

  test('dates match a year, month, day, month name or range', () {
    for (final text in [
      'date:2026',
      'date:2026-10',
      'date:2026/10/17',
      'date:october',
      'date:oct',
      'date:2026-09..2026-10',
      'date:2026..',
      'date:..2026-10-17',
    ]) {
      expect(_matches(text, _beach, _beachEntry), isTrue, reason: text);
    }
    for (final text in ['date:2025', 'date:2026-10-18', 'date:..2026-09']) {
      expect(_matches(text, _beach, _beachEntry), isFalse, reason: text);
    }
    expect(_matches('date:2026', _item('undated.jpg'), null), isFalse);
  });

  test('locations match whether known, or near a point', () {
    expect(_matches('location:', _beach, _beachEntry), isTrue);
    expect(_matches('location:yes', _beach, _beachEntry), isTrue);
    expect(_matches('location:no', _office, _officeEntry), isTrue);
    expect(_matches('location:-35.3,149.1', _beach, _beachEntry), isTrue);
    expect(_matches('location:-33.87,151.21', _beach, _beachEntry), isFalse);
    expect(_matches('location:-35.3,149.1,1', _beach, _beachEntry), isFalse);
    expect(_matches('location:-33.87,151.21,300', _beach, _beachEntry), isTrue);
  });

  test('a place given by the user is found by name and stands in for EXIF', () {
    final entry = _officeEntry.withPlace(
      const PhotoPlace(
        'Sydney, New South Wales',
        latitude: -33.87,
        longitude: 151.21,
      ),
    );
    expect(_matches('location:sydney', _office, entry), isTrue);
    expect(_matches('sydney', _office, entry), isTrue);
    expect(_matches('location:canberra', _office, entry), isFalse);
    expect(_matches('location:yes', _office, entry), isTrue);
    expect(_matches('location:-33.9,151.2,5', _office, entry), isTrue);

    final moved = _beachEntry.withPlace(
      const PhotoPlace('Sydney', latitude: -33.87, longitude: 151.21),
    );
    expect(_matches('location:-35.3,149.1', _beach, moved), isFalse);
  });

  test('terms that cannot be understood are reported and left out', () {
    final search = MediaSearch.parse('date:soon beach');
    expect(search.problems, hasLength(1));
    expect(search.terms.single.value, 'beach');
  });

  test('the shared filter tells its listeners of a new search', () {
    final filter = MediaFilter();
    var told = 0;
    filter.addListener(() => told++);
    filter.text = 'tag:beach';
    filter.text = 'tag:beach';
    expect(told, 1);
    expect(filter.isActive, isTrue);
    filter.clear();
    expect(filter.isActive, isFalse);
    expect(told, 2);
  });
}
