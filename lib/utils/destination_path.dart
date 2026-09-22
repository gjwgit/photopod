/// Keep a destination path inside the album.
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

import 'package:photopod/constants/media.dart';

/// Where a copy or a move should put its items, and what to call them.

class Destination {
  /// The Pod-relative path of the folder to write into, with each segment
  /// percent-encoded.

  final String folderPath;

  /// The name to give the item once it is there, or null to keep its own.
  ///
  /// This is a display name, so `beach.jpg` rather than `beach.jpg.enc.ttl`.

  final String? newName;

  const Destination(this.folderPath, {this.newName});

  /// Whether the user asked for the item to be renamed on the way.

  bool get renames => newName != null;
}

/// Read [typed] as a destination inside [rootPath], or return null when it
/// would lead out of the album.
///
/// The last part of the path is taken as a new file name when it carries an
/// extension PhotoPod displays, so `holiday/sunset.jpg` means "put it in
/// holiday and call it sunset.jpg" while `holiday/2026` means "put it in the
/// 2026 folder". A trailing slash always says folder, which is the way to
/// name a folder that would otherwise look like a file.
///
/// The album root is a fixed prefix rather than a starting suggestion. A `..`
/// segment is refused rather than quietly dropped, so that a copy or a move
/// can never reach the profile, the encryption keys, or anything else in the
/// Pod that PhotoPod has no business writing to. A root that has been pasted
/// back in is tolerated and dropped, since the field already shows it.

Destination? resolveDestination(String rootPath, String typed) {
  final trimmed = typed.trim();
  final saysFolder = trimmed.endsWith('/');

  var text = trimmed.replaceAll(RegExp(r'^/+|/+$'), '');

  if (text == rootPath) {
    text = '';
  } else if (text.startsWith('$rootPath/')) {
    text = text.substring(rootPath.length + 1);
  }

  final segments = text
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .map((segment) => segment.trim())
      .toList();

  if (segments.any((segment) => segment == '.' || segment == '..')) {
    return null;
  }

  if (segments.isEmpty) return Destination(rootPath);

  final last = segments.last;
  final namesFile = !saysFolder && kindOf(last) != null;
  final folders = namesFile
      ? segments.sublist(0, segments.length - 1)
      : segments;

  final folderPath = folders.isEmpty
      ? rootPath
      : '$rootPath/${folders.map(Uri.encodeComponent).join('/')}';

  return Destination(folderPath, newName: namesFile ? last : null);
}
