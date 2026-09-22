/// The media formats PhotoPod understands.
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

import 'package:flutter/material.dart';

/// The two kinds of media PhotoPod manages, each with its own section in the
/// navigation bar.

enum MediaKind {
  /// Still images: JPG, JPEG, PNG, GIF and TIFF.

  photo('Photos', Icons.photo_library),

  /// Moving images: MP4 and MOV.

  video('Videos', Icons.video_library);

  /// Label shown in the navigation bar and in dialogue titles.

  final String label;

  /// Icon shown in the navigation bar.

  final IconData icon;

  const MediaKind(this.label, this.icon);

  /// The extensions, without a leading dot and in lower case, that belong to
  /// this kind of media.

  Set<String> get extensions =>
      this == MediaKind.photo ? photoExtensions : videoExtensions;

  /// The singular noun used in user-facing messages.

  String get noun => this == MediaKind.photo ? 'photo' : 'video';
}

/// Photo formats PhotoPod displays. TIFF carries two conventional extensions
/// and both are accepted.

const Set<String> photoExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'tiff',
  'tif',
};

/// Video formats PhotoPod displays.

const Set<String> videoExtensions = {'mp4', 'mov'};

/// Media types sent to the Solid server when a file is added, and used when
/// handing bytes to the video player. A Solid server stores whatever content
/// type it is given, so getting this right keeps the files usable by other
/// applications reading the same Pod.

const Map<String, String> mediaContentTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'tiff': 'image/tiff',
  'tif': 'image/tiff',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
};

/// The lower case extension of [name], without the leading dot. Returns an
/// empty string when the name carries no extension.

String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// The media kind [name] belongs to, or null when PhotoPod does not handle
/// the format.

MediaKind? kindOf(String name) {
  final ext = extensionOf(name);
  if (photoExtensions.contains(ext)) return MediaKind.photo;
  if (videoExtensions.contains(ext)) return MediaKind.video;
  return null;
}

/// The content type to send when storing [name] on the Pod, falling back to a
/// generic binary type for anything unrecognised.

String contentTypeOf(String name) =>
    mediaContentTypes[extensionOf(name)] ?? 'application/octet-stream';

/// The suffix solidpod gives an encrypted resource.
///
/// Every Pod app in this family stores its data encrypted and in Turtle, and
/// solidpod refuses to encrypt a resource whose name does not end in `.ttl`.
/// A photo called `beach.jpg` is therefore stored as `beach.jpg.enc.ttl`,
/// which is also the only shape the shared file browsers will show.

const String encryptedSuffix = '.enc.ttl';

/// The name to show the user for a resource stored as [storedName].
///
/// Strips the encryption suffix, so `beach.jpg.enc.ttl` reads as `beach.jpg`.
/// A name without the suffix is returned unchanged, which is what keeps any
/// plain file already sitting in the album visible.

String displayNameOf(String storedName) => storedName.endsWith(encryptedSuffix)
    ? storedName.substring(0, storedName.length - encryptedSuffix.length)
    : storedName;

/// The resource name to store a file called [displayName] under.

String storedNameOf(String displayName) => '$displayName$encryptedSuffix';

/// TIFF has no Flutter codec, so those files take the slower path through the
/// `image` package before they can be displayed.

bool isTiff(String name) {
  final ext = extensionOf(name);
  return ext == 'tiff' || ext == 'tif';
}
