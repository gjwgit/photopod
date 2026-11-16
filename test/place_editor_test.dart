/// Tests for looking up places and choosing one in Get Info.
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

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/services/geocoder.dart';
import 'package:photopod/widgets/place_editor.dart';

void main() {
  group('geocode', () {
    test('takes coordinates as they stand, without asking', () async {
      final client = MockClient((_) async => fail('no request expected'));
      final places = await geocode(' -35.28, 149.13 ', client: client);
      expect(places.single.latitude, -35.28);
      expect(places.single.longitude, 149.13);
      expect(placeFromCoordinates('95, 10'), isNull);
      expect(placeFromCoordinates('Canberra'), isNull);
    });

    test('asks Nominatim and reads what it finds', () async {
      late Uri asked;
      final client = MockClient((request) async {
        asked = request.url;
        return http.Response(
          jsonEncode([
            {
              'display_name': 'Canberra, Australian Capital Territory',
              'lat': '-35.2975906',
              'lon': '149.1012676',
            },
            {'display_name': 'Broken', 'lat': 'x', 'lon': '1'},
          ]),
          200,
        );
      });
      final places = await geocode('Canberra', client: client);
      expect(asked.host, 'nominatim.openstreetmap.org');
      expect(asked.queryParameters['q'], 'Canberra');
      expect(places, hasLength(1));
      expect(places.single.name, startsWith('Canberra'));
      expect(places.single.latitude, closeTo(-35.30, 0.01));
      expect(places.single.source, userSource);
    });

    test('says when the lookup fails', () async {
      final client = MockClient((_) async => http.Response('busy', 503));
      expect(geocode('Canberra', client: client), throwsException);
    });
  });

  test('a place survives a round trip through the catalog', () {
    final entry = const CatalogEntry('photopod/data/a.jpg').withPlace(
      const PhotoPlace('Canberra', latitude: -35.3, longitude: 149.1),
    );
    final back = CatalogEntry.fromJson(
      jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>,
    )!;
    expect(back.place!.name, 'Canberra');
    expect(back.location, (-35.3, 149.1));
    expect(back.withTitle(const PhotoTitle('x')).place, isNotNull);
    expect(back.copyWith(tags: const []).place, isNotNull);
    expect(
      PhotoPlace.fromJson({'name': 'x', 'latitude': 91, 'longitude': 0}),
      isNull,
    );
  });

  testWidgets('a place looked up is chosen from those found', (tester) async {
    PhotoPlace? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaceEditor(
            place: null,
            onChanged: (place) => chosen = place,
            lookup: (text) async => const [
              PhotoPlace('Richmond, Victoria', latitude: -37.8, longitude: 145),
              PhotoPlace(
                'Richmond, Virginia',
                latitude: 37.5,
                longitude: -77.4,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Richmond');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(chosen, isNull);
    await tester.tap(find.text('Richmond, Virginia'));
    await tester.pumpAndSettle();
    expect(chosen!.longitude, -77.4);
    expect(find.text('Richmond, Victoria'), findsNothing);
  });

  testWidgets('the place given can be taken away', (tester) async {
    var told = false;
    PhotoPlace? chosen = const PhotoPlace('x', latitude: 0, longitude: 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaceEditor(
            place: const PhotoPlace('Canberra', latitude: -35, longitude: 149),
            onChanged: (place) {
              told = true;
              chosen = place;
            },
          ),
        ),
      ),
    );
    expect(find.text('Canberra'), findsOneWidget);
    await tester.tap(find.byTooltip('Forget this place'));
    expect(told, isTrue);
    expect(chosen, isNull);
  });
}
