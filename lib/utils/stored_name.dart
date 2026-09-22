/// PhotoPod - derive the Pod resource name for an uploaded photo.
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

import 'package:photopod/constants/app.dart';

/// Characters a Solid server is happy to see in a resource name. Anything
/// else in the picked filename is replaced with an underscore.

final _unsafe = RegExp(r'[^a-zA-Z0-9._\-]');

/// The encrypted resource name for [fileName], unique within [taken].
///
/// Two photos picked from different folders very often share a name
/// (`IMG_1234.jpg`), and the second upload must not overwrite the first, so a
/// `(1)`, `(2)`, ... suffix is appended to the base name until the result is
/// unused. [taken] is the set of stored names already in the index.
///
/// Returns the full stored name, e.g. `IMG_1234(1).jpg.enc.ttl`.

String storedNameFor(String fileName, Set<String> taken) {
  final safe = fileName.replaceAll(_unsafe, '_');
  if (!taken.contains('$safe$encryptedSuffix')) return '$safe$encryptedSuffix';

  final dot = safe.lastIndexOf('.');
  final base = dot > 0 ? safe.substring(0, dot) : safe;
  final ext = dot > 0 ? safe.substring(dot) : '';

  for (var n = 1; ; n++) {
    final candidate = '$base($n)$ext$encryptedSuffix';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// The original filename recovered from [storedName], i.e. with the
/// encryption suffix removed. Used when naming an exported file and when
/// choosing a MIME type from the extension.

String originalName(String storedName) =>
    storedName.endsWith(encryptedSuffix)
    ? storedName.substring(0, storedName.length - encryptedSuffix.length)
    : storedName;

/// Best-guess MIME type for [fileName], from its extension.

String mimeTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return 'application/octet-stream';
  final ext = fileName.substring(dot + 1).toLowerCase();
  return _mimeTypes[ext] ?? 'application/octet-stream';
}

const _mimeTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'heic': 'image/heic',
};
