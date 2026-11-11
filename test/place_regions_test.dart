/// Tests for naming the region a photo was taken in, and grouping by it.
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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/place_regions.dart';
import 'package:photopod/widgets/timeline_layout.dart';

MediaItem _file(String name, DateTime? modified) => MediaItem(
  name: name,
  rawName: name,
  path: 'photopod/data/$name',
  url: 'https://pod.example/photopod/data/$name',
  isFolder: false,
  modified: modified,
);

void main() {
  group('PlaceRegions', () {
    // The bundled regions, read as the app reads them.

    final regions = PlaceRegions.parse(
      File('assets/places/regions.tsv').readAsStringSync(),
    );

    test('names the city a point belongs to, not its suburb', () {
      expect(regions.nearest(-35.238, 149.066), 'Canberra, Australia');
      expect(regions.nearest(-35.42, 149.09), 'Canberra, Australia');
      expect(regions.nearest(-33.80, 151.285), 'Sydney, Australia');
      expect(regions.nearest(48.886, 2.343), 'Paris, France');
    });

    test('keeps a city of its own beside a larger one', () {
      expect(regions.nearest(43.70, 7.27), 'Nice, France');
      expect(regions.nearest(35.01, 135.77), 'Kyoto, Japan');
    });

    test('names a city-state by itself', () {
      expect(regions.nearest(1.354, 103.945), 'Singapore');
      expect(regions.nearest(22.32, 114.17), 'Hong Kong');
    });

    test('tells apart places of the same name by their state', () {
      expect(
        regions.nearest(45.52, -122.68),
        'Portland, Oregon, United States',
      );
      expect(regions.nearest(43.66, -70.26), 'Portland, Maine, United States');
    });

    test('finds the nearest region far from any city', () {
      expect(regions.nearest(-25.344, 131.036), 'Alice Springs, Australia');
      expect(regions.nearest(-89.9, 0), isNotNull);
      expect(regions.nearest(0, 179.99), isNotNull);
    });

    test('puts a photo that does not say where under Others', () {
      PlaceRegions.instance = regions;
      addTearDown(() => PlaceRegions.instance = null);
      expect(PlaceRegions.regionOf(null), unknownRegion);
      expect(PlaceRegions.regionOf((1.29, 103.85)), 'Singapore');
    });
  });

  group('groupByPlace', () {
    test('lists places A to Z, newest first, with Others last', () {
      final where = {
        'a.jpg': 'Nice, France',
        'b.jpg': unknownRegion,
        'c.jpg': 'Canberra, Australia',
        'd.jpg': 'Canberra, Australia',
        'e.jpg': 'Singapore',
      };
      final items = [
        _file('a.jpg', DateTime(2024)),
        _file('b.jpg', DateTime(2025)),
        _file('c.jpg', DateTime(2020)),
        _file('d.jpg', DateTime(2023)),
        _file('e.jpg', null),
      ];

      final groups = groupByPlace(items, (item) => where[item.name]!);

      expect(groups.map((group) => group.label), [
        'Canberra, Australia',
        'Nice, France',
        'Singapore',
        unknownRegion,
      ]);
      expect(groups.first.items.map((item) => item.name), ['d.jpg', 'c.jpg']);
      expect(groups.every((group) => group.day == null), isTrue);
    });
  });
}
