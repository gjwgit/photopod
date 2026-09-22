/// PhotoPod - Pod paths and URLs for the photo and thumbnail resources.
///
// Time-stamp: <Sunday 2026-08-30 14:14:09 +1000 Graham Williams>
///
/// Copyright (C) 2026, Togaware Pty Ltd
///
/// Licensed under the GNU General Public License, Version 3 (the "License");
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
// this program.  If not, see <https://opensource.org/license/gpl-3-0>.
///
/// Authors: Graham Williams

library;

import 'package:solidpod/solidpod.dart' show getDataDirPath, getDirUrl;

import 'package:photopod/constants/app.dart';

/// Two flavours of path are in play and it is easy to confuse them.
///
/// * `writePod` and `readPod` take a path RELATIVE TO the app data directory,
///   e.g. `photos/IMG_1234.jpg.enc.ttl`. The [relPhoto], [relThumb] and
///   [relIndex] helpers below build those.
/// * `getDirUrl` and `deleteFile` take a path relative to the POD ROOT, e.g.
///   `photopod/data/photos`. The [photosDirUrl] and [thumbsDirUrl] helpers
///   build those, and they are async because the app directory name is only
///   known once solidpod has been configured.

/// Path of a photo resource, relative to the data directory.

String relPhoto(String storedName) => '$photosDirName/$storedName';

/// Path of a thumbnail resource, relative to the data directory.
///
/// A thumbnail shares its stored name with its photo, so one name locates
/// both and no extra bookkeeping is needed to pair them up.

String relThumb(String storedName) => '$thumbsDirName/$storedName';

/// Path of the photo index, relative to the data directory.

String relIndex() => '$photosDirName/$photoIndexFileName';

/// URL of the photos container, used to set up its inherited encryption key.

Future<String> photosDirUrl() async =>
    getDirUrl('${await getDataDirPath()}/$photosDirName');

/// URL of the thumbnails container.

Future<String> thumbsDirUrl() async =>
    getDirUrl('${await getDataDirPath()}/$thumbsDirName');
