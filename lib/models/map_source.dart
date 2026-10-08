/// The tile servers the map can be drawn from.
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

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// The map providers offered in Map Settings, the same set GeoPod offers.

enum MapSource {
  /// The standard OpenStreetMap street map.

  openStreetMap(
    'OpenStreetMap',
    'Classic open source map',
    Icons.map,
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'OpenStreetMap contributors',
    19,
  ),

  /// Carto's colourful, detailed street map.

  cartoVoyager(
    'CartoDB Voyager',
    'Colourful and detailed',
    Icons.map,
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
    'OpenStreetMap contributors, CARTO',
    20,
    subdomains: ['a', 'b', 'c', 'd'],
  ),

  /// Carto's dark map, which is easier on the eyes at night.

  cartoDarkMatter(
    'CartoDB Dark Matter',
    'Night-optimised dark theme',
    Icons.dark_mode,
    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
    'OpenStreetMap contributors, CARTO',
    20,
    subdomains: ['a', 'b', 'c', 'd'],
  ),

  /// Carto's pale greyscale map, which lets the photos stand out.

  cartoPositron(
    'CartoDB Positron',
    'Light greyscale design',
    Icons.map,
    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
    'OpenStreetMap contributors, CARTO',
    20,
    subdomains: ['a', 'b', 'c', 'd'],
  ),

  /// Esri's street map.

  esriWorldStreetMap(
    'Esri Street Map',
    'Professional street map',
    Icons.map,
    'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'World_Street_Map/MapServer/tile/{z}/{y}/{x}',
    'Esri',
    19,
  ),

  /// Esri's satellite imagery.

  esriWorldImagery(
    'Esri Satellite',
    'High-resolution satellite',
    Icons.satellite_alt,
    'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'World_Imagery/MapServer/tile/{z}/{y}/{x}',
    'Esri, Maxar, Earthstar Geographics',
    17,
  ),

  /// Esri's topographic map, and the default.

  esriWorldTopo(
    'Esri Topographic',
    'Topographic with contours',
    Icons.terrain,
    'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
    'Esri',
    18,
  ),

  /// OpenTopoMap's free topographic map.

  openTopoMap(
    'OpenTopoMap',
    'Free topographic map',
    Icons.terrain,
    'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    'OpenStreetMap contributors, SRTM, OpenTopoMap',
    17,
    subdomains: ['a', 'b', 'c'],
  ),

  /// CyclOSM, which picks out cycle paths.

  cyclOSM(
    'CyclOSM',
    'Optimised for cycling',
    Icons.directions_bike,
    'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
    'OpenStreetMap contributors, CyclOSM',
    18,
    subdomains: ['a', 'b', 'c'],
  );

  /// Name shown in the dropdown.

  final String label;

  /// One line saying what the map looks like.

  final String description;

  /// Icon shown beside the name.

  final IconData icon;

  /// Where the tiles come from.

  final String urlTemplate;

  /// Who the tiles must be credited to.

  final String attribution;

  /// The deepest zoom the server has tiles for; beyond it the last tiles are
  /// scaled up.

  final int maxNativeZoom;

  /// Hosts the tiles are shared across, filling `{s}` in [urlTemplate].

  final List<String> subdomains;

  const MapSource(
    this.label,
    this.description,
    this.icon,
    this.urlTemplate,
    this.attribution,
    this.maxNativeZoom, {
    this.subdomains = const [],
  });

  static const _key = 'photopod.mapSource';

  /// The provider chosen on this device, or Esri Topographic when none has
  /// been chosen yet or the stored one is no longer offered.

  static Future<MapSource> load() async {
    final name = (await SharedPreferences.getInstance()).getString(_key);
    return MapSource.values.firstWhere(
      (source) => source.name == name,
      orElse: () => MapSource.esriWorldTopo,
    );
  }

  /// Remember the provider on this device. Like the browser's view options it
  /// is a matter of taste for this screen, so it is never written to the Pod.

  Future<void> save() async =>
      (await SharedPreferences.getInstance()).setString(_key, name);
}
