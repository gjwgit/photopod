/// Face detection and recognition, where the platform can run it.
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
import 'package:photopod/services/face_engine_native.dart'
    if (dart.library.js_interop) 'package:photopod/services/face_engine_stub.dart'
    as platform;

/// The face engine: YuNet finds the faces in a photo and SFace describes
/// each one, all on this device.
///
/// opencv_dart reaches OpenCV through dart:ffi, which the web does not have,
/// so the web build gets stand-ins that report face recognition as
/// unavailable. As with HealthPod's analyser channel, the native engine is
/// the default and the platform files offer top-level functions of the same
/// names, so that Dart Code Metrics sees both sides in use.

class FaceEngine {
  const FaceEngine._();

  /// Whether this platform can recognise faces at all.

  static bool get isSupported => platform.faceEngineSupported();

  /// Fetch the models if need be and get the engine ready. [onStatus] hears
  /// what is happening, for the status line.

  static Future<void> start({void Function(String)? onStatus}) =>
      platform.startFaceEngine(onStatus: onStatus);

  /// The faces in [image], an encoded JPEG, PNG or similar.

  static Future<List<FoundFace>> analyse(Uint8List image) =>
      platform.analyseFaces(image);

  /// Shut the engine down, as on logout. It starts again when next needed.

  static void stop() => platform.stopFaceEngine();
}
