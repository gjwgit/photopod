/// The names PhotoPod is allowed to give a resource on the Pod.
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

/// The characters a file name the user sees may not hold.
///
/// A file's own name never reaches a URL, since it is stored under a random
/// one, so any script and any spacing will do. What is left out is what no
/// common file system accepts, which is where a downloaded photo ends up:
/// the path separators, `: * ? " < > |` that Windows refuses, and control
/// characters.

final RegExp _forbiddenInFileName = RegExp(r'[/\\:*?"<>|\x00-\x1f\x7f]');

/// The single character in the file name [name] that keeps it from being
/// used as it stands, or null when there is none.

String? firstForbiddenFileNameCharacter(String name) =>
    _forbiddenInFileName.firstMatch(name)?.group(0);

/// [name], the name a file arrived with, made fit to be shown and later
/// saved back to a file system: every forbidden character becomes an
/// underscore and surrounding spaces go. Letters of every script are kept,
/// so `海滩 照片.jpg` stays exactly as it is.

String safeFileName(String name) {
  final replaced = name.replaceAll(_forbiddenInFileName, '_').trim();
  if (replaced.isEmpty) return 'file';

  // A name that begins with a full stop reads as a hidden file once it is
  // downloaded.

  return replaced.startsWith('.') ? 'file$replaced' : replaced;
}
