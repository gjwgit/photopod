/// TeePod where it cannot be reached: the web.
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

import 'package:photopod/constants/teepod.dart';
import 'package:photopod/services/teepod/teepod_types.dart';

/// TeePod as the web build sees it: never there. See teepod_io.dart.

class TeePod {
  TeePod._();

  /// Whether this platform can reach TeePod at all.

  static const bool isSupported = false;

  static Future<TeePod> connect(TeePodConfig config) =>
      throw UnsupportedError('TeePod cannot be reached from a browser.');

  Stream<TeePodAnswer> analyse(
    Stream<TeePodImage> images,
    TeePodService service,
  ) => throw UnsupportedError('TeePod cannot be reached from a browser.');

  Future<void> close() async {}
}
