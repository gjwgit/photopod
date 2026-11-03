/// Face recognition on a platform that cannot run it: the web.
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

import 'dart:typed_data';

import 'package:photopod/models/face_book.dart';

// Stand-ins for the OpenCV engine on the web, matching the functions of
// face_engine_native.dart.

bool faceEngineSupported() => false;

Future<void> startFaceEngine({void Function(String)? onStatus}) async =>
    throw UnsupportedError('Face recognition is not available on the web.');

Future<List<FoundFace>> analyseFaces(Uint8List image) async =>
    throw UnsupportedError('Face recognition is not available on the web.');

void stopFaceEngine() {}
