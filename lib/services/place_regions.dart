/// Name the city and country a photo was taken in, from where it was taken.
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

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

/// The heading for photos that do not say where they were taken.

const String unknownRegion = 'Others';

/// Where the places are bundled; see `support/make_place_regions.py`.

const String _asset = 'assets/places/regions.tsv';

/// One place a photo can be grouped under.

class _Region {
  const _Region(this.label, this.latitude, this.longitude);

  /// Such as `Canberra, Australia`, `Nice, France` or `Singapore`.

  final String label;

  final double latitude;

  final double longitude;
}

/// The administrative region a point on the map belongs to, such as
/// `Canberra, Australia`, `Nice, France` or `Singapore`.
///
/// The regions are the national capitals and the seats of the first- and
/// second-level administrative divisions GeoNames lists, bundled with the
/// app, and a point belongs to the nearest of them. Nothing is looked up
/// over the network, so where the user's photos were taken never leaves the
/// device, and the answer is there at once, which sorting needs.

class PlaceRegions {
  PlaceRegions._(List<_Region> regions) {
    for (final region in regions) {
      _cells
          .putIfAbsent(
            _cellOf(region.latitude, region.longitude),
            () => <_Region>[],
          )
          .add(region);
    }
  }

  /// Build from the text of the bundled file, for the tests.

  @visibleForTesting
  factory PlaceRegions.parse(String text) => PlaceRegions._(_parse(text));

  static PlaceRegions? _instance;
  static Future<void>? _loading;

  /// The regions once [load] has read them, or null before then.

  static PlaceRegions? get instance => _instance;

  /// Replace the regions in use, for the tests.

  @visibleForTesting
  static set instance(PlaceRegions? regions) => _instance = regions;

  /// Read the bundled regions, once. A failure leaves every photo under
  /// [unknownRegion] rather than stopping the app.

  static Future<void> load() => _loading ??= () async {
    try {
      _instance = PlaceRegions.parse(await rootBundle.loadString(_asset));
    } on Object catch (e) {
      debugPrint('PhotoPod could not read the place regions: $e');
    }
  }();

  /// The region the point at [latitude], [longitude] belongs to, or
  /// [unknownRegion] when there is no point or the regions are not loaded.

  static String regionOf((double, double)? location) {
    final regions = _instance;
    if (location == null || regions == null) return unknownRegion;
    return regions.nearest(location.$1, location.$2) ?? unknownRegion;
  }

  // The regions in cells of one degree of latitude by one of longitude, so
  // that the search for the nearest looks at the few cells around a point
  // rather than at all of them.

  final Map<int, List<_Region>> _cells = {};

  // The answers already given. A library holds many photos from each place,
  // so most are asked for again and again as the list is sorted. The points
  // are rounded to about a hundred metres, far closer than any two regions.

  final Map<int, String?> _answers = {};

  static int _cellOf(double latitude, double longitude) =>
      _key(latitude.floor(), longitude.floor());

  static int _key(int row, int column) =>
      (row + 90) * 360 + (column + 180) % 360;

  /// The label of the region nearest to [latitude], [longitude], or null
  /// when there are no regions at all.

  String? nearest(double latitude, double longitude) {
    final memo =
        ((latitude * 1000).round() + 90000) * 360001 +
        (longitude * 1000).round() +
        180000;
    return _answers.putIfAbsent(memo, () => _search(latitude, longitude));
  }

  String? _search(double latitude, double longitude) {
    final row = latitude.floor();
    final column = longitude.floor();
    _Region? best;
    var bestKm = double.infinity;

    // Look ring by ring outwards from the point's own cell. Anything beyond
    // ring r is more than r degrees of latitude or of longitude away, and a
    // degree of longitude is narrowest at the ring's most poleward edge, so
    // once the best found is nearer than that, nothing further can beat it.

    for (var ring = 0; ring <= 180; ring++) {
      for (var r = row - ring; r <= row + ring; r++) {
        if (r < -90 || r > 89) continue;
        final onEdge = r == row - ring || r == row + ring;
        final step = onEdge || ring == 0 ? 1 : 2 * ring;
        for (var c = column - ring; c <= column + ring; c += step) {
          for (final region in _cells[_key(r, c)] ?? const <_Region>[]) {
            final km = _distanceKm(
              latitude,
              longitude,
              region.latitude,
              region.longitude,
            );
            if (km < bestKm) {
              bestKm = km;
              best = region;
            }
          }
        }
      }
      final edge = math.min(89.0, latitude.abs() + ring + 1);
      final reach = ring * 111.0 * math.cos(edge * math.pi / 180);
      if (best != null && bestKm <= reach) break;
    }
    return best?.label;
  }

  static List<_Region> _parse(String text) {
    final regions = <_Region>[];
    for (final line in text.split('\n')) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.trimRight().split('\t');
      if (parts.length != 3) continue;
      final latitude = double.tryParse(parts[1]);
      final longitude = double.tryParse(parts[2]);
      if (latitude == null || longitude == null) continue;
      regions.add(_Region(parts[0], latitude, longitude));
    }
    return regions;
  }
}

// The great-circle distance between two points, in kilometres.

double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const radians = math.pi / 180;
  final dLat = (lat2 - lat1) * radians;
  final dLon = (lon2 - lon1) * radians;
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * radians) *
          math.cos(lat2 * radians) *
          math.pow(math.sin(dLon / 2), 2);
  return 12742 * math.asin(math.sqrt(h.toDouble()));
}
