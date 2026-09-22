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

/// The Pod-relative destination path for [typed], or null when it would lead
/// out of [rootPath].
///
/// The album root is a fixed prefix rather than a starting suggestion. A `..`
/// segment is refused rather than quietly dropped, so that a copy or a move
/// can never reach the profile, the encryption keys, or anything else in the
/// Pod that PhotoPod has no business writing to. A root that has been pasted
/// back in is tolerated and dropped, since the field already shows it, and
/// each remaining segment is percent-encoded so a folder name with a space in
/// it still produces a usable URL.

String? resolveDestination(String rootPath, String typed) {
  var text = typed.trim().replaceAll(RegExp(r'^/+|/+$'), '');

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

  if (segments.isEmpty) return rootPath;

  return '$rootPath/${segments.map(Uri.encodeComponent).join('/')}';
}
