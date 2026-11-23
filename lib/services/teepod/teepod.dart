/// TeePod, the trusted image analyser, where the platform can reach it.
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

// TeePod is reached over gRPC with a client certificate and a pinned server
// certificate, which needs dart:io sockets. A browser can do neither, so the
// web build gets a TeePod that is never available, and keeps using the Pod
// Analyser.

export 'package:photopod/services/teepod/teepod_types.dart';
export 'package:photopod/services/teepod/teepod_stub.dart'
    if (dart.library.io) 'package:photopod/services/teepod/teepod_io.dart';
