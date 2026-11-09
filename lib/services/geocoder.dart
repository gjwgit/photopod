/// Turn the name of a place into the point on the map it stands for.
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

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:http/http.dart' as http;

import 'package:photopod/models/catalog_entry.dart';

/// Who is asked, which is OpenStreetMap's Nominatim, the same project whose
/// tiles the map draws by default. Only the text the user types is sent.

const String geocoderName = 'OpenStreetMap';

const String _endpoint = 'https://nominatim.openstreetmap.org/search';

/// How many places are offered to choose from.

const int maxGeocodedPlaces = 5;

/// The point [text] gives as `latitude, longitude`, such as `-35.28, 149.13`,
/// which needs no looking up, or null when it is not one.

PhotoPlace? placeFromCoordinates(String text) {
  final parts = text.split(',').map((part) => double.tryParse(part.trim()));
  final numbers = parts.toList();
  if (numbers.length != 2 || numbers.contains(null)) return null;
  final latitude = numbers[0]!;
  final longitude = numbers[1]!;
  if (latitude.abs() > 90 || longitude.abs() > 180) return null;
  return PhotoPlace(
    '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
    latitude: latitude,
    longitude: longitude,
  );
}

/// The places matching [text], best first, each with the full name the
/// geocoder knows it by. Coordinates are taken as they stand, without asking.
///
/// Nominatim asks that each application say who it is and send no more than
/// one request a second, which a search made only when the user asks for
/// one keeps well within. A browser sends its own User-Agent and will not let
/// it be replaced, and the page it is on says who is asking instead.

Future<List<PhotoPlace>> geocode(String text, {http.Client? client}) async {
  final query = text.trim();
  if (query.isEmpty) return const [];
  final point = placeFromCoordinates(query);
  if (point != null) return [point];

  final uri = Uri.parse(_endpoint).replace(
    queryParameters: {
      'q': query,
      'format': 'jsonv2',
      'limit': '$maxGeocodedPlaces',
    },
  );
  final headers = {
    if (!kIsWeb) 'User-Agent': 'PhotoPod (https://github.com/gjwgit/photopod)',
  };

  final http.Response response;
  if (client == null) {
    final own = http.Client();
    try {
      response = await own
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
    } finally {
      own.close();
    }
  } else {
    response = await client.get(uri, headers: headers);
  }

  if (response.statusCode != 200) {
    throw Exception(
      '$geocoderName could not look up "$query" '
      '(HTTP ${response.statusCode})',
    );
  }
  final results = jsonDecode(utf8.decode(response.bodyBytes));
  if (results is! List) return const [];
  return [for (final result in results) ?_placeOf(result)];
}

PhotoPlace? _placeOf(Object? result) {
  if (result is! Map<String, dynamic>) return null;
  final name = result['display_name'];
  final latitude = double.tryParse('${result['lat']}');
  final longitude = double.tryParse('${result['lon']}');
  if (name is! String || latitude == null || longitude == null) return null;
  return PhotoPlace(name, latitude: latitude, longitude: longitude);
}
