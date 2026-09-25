/// Check a name is usable as a Pod resource.
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
import 'package:photopod/utils/resource_name.dart';

/// The longest name PhotoPod will accept.
///
/// A Solid resource name ends up inside a URL and, once downloaded, inside a
/// file name on the user's own machine. 128 characters stays comfortably
/// within the limits of every common file system.

const int maxNameLength = 128;

/// Check [name] as a new name for a file or folder, returning the reason it
/// cannot be used, or null when it is fine.
///
/// [isFolder] relaxes the extension check, and [originalName] lets a media
/// file's extension be compared with the one it already has, so that a rename
/// cannot quietly move a photo out of the view it is sitting in.

String? validateName(
  String name, {
  required bool isFolder,
  String? originalName,
}) {
  final trimmed = name.trim();

  if (trimmed.isEmpty) {
    return 'The name cannot be empty.';
  }

  if (trimmed.length > maxNameLength) {
    return 'The name is too long. Please use at most $maxNameLength '
        'characters.';
  }

  if (trimmed != name) {
    return 'The name cannot begin or end with a space.';
  }

  // A name that would have to be percent-escaped inside a URL cannot be used,
  // because the encryption key for the resource would then be filed under a
  // different URL from the one it is looked up by. See [safeResourceName].

  final invalid = firstUnsafeCharacter(name);
  if (invalid != null) {
    final display = invalid == ' '
        ? 'a space'
        : invalid.codeUnitAt(0) < 0x20
        ? 'a control character'
        : '"$invalid"';
    return 'The name cannot contain $display. Please use letters, digits, '
        "and any of - _ . ! ~ * ' ( ) only.";
  }

  if (trimmed == '.' || trimmed == '..') {
    return 'The name cannot be "." or "..".';
  }

  if (trimmed.startsWith('.')) {
    return 'The name cannot start with a full stop.';
  }

  if (trimmed.endsWith('.')) {
    return 'The name cannot end with a full stop.';
  }

  if (isFolder) return null;

  final kind = kindOf(trimmed);
  if (kind == null) {
    return 'The name needs an extension PhotoPod can display: '
        '${_formatList(photoExtensions)} for photos, or '
        '${_formatList(videoExtensions)} for videos.';
  }

  if (originalName != null && kindOf(originalName) != kind) {
    return 'Changing the extension would move this file out of the '
        '${kind.label} view. Please keep a '
        '${kindOf(originalName)?.noun ?? 'media'} extension.';
  }

  return null;
}

String _formatList(Set<String> extensions) =>
    extensions.map((e) => '.$e').join(', ');
