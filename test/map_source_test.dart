/// Tests for the map provider stored on this device.
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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:photopod/models/map_source.dart';

void main() {
  test('defaults to Esri Topographic when nothing is chosen', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await MapSource.load(), MapSource.esriWorldTopo);
  });

  test(
    'defaults to Esri Topographic for a provider no longer offered',
    () async {
      SharedPreferences.setMockInitialValues({'photopod.mapSource': 'gone'});
      expect(await MapSource.load(), MapSource.esriWorldTopo);
    },
  );

  test('keeps a provider that was chosen', () async {
    SharedPreferences.setMockInitialValues({});
    await MapSource.openStreetMap.save();
    expect(await MapSource.load(), MapSource.openStreetMap);
  });
}
