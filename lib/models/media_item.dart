/// A single photo, video or folder held in the Pod.
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

/// One entry in a Pod container: either a folder or a media file.
///
/// Both a Pod-relative [path] (such as `photopod/data/holiday/beach.jpg`) and
/// an absolute [url] are kept. The path is what solidpod's permission and
/// container helpers expect, while the URL is what the REST calls need, and
/// deriving one from the other costs a round trip we can avoid.

class MediaItem {
  /// Display name, including the extension for files. Percent-escapes that
  /// appear in the resource name are decoded here, so a file stored as
  /// `my%20photo.jpg` reads as `my photo.jpg`.

  final String name;

  /// The name exactly as the server spells it, still percent-encoded.
  ///
  /// Paths and URLs are always built from this rather than from [name],
  /// because solidpod's URL helpers join path segments verbatim: handing them
  /// a decoded name would produce a URL with a raw space in it.

  final String rawName;

  /// Path relative to the Pod root, with no trailing slash even for a
  /// folder, which is the shape solidpod's path helpers expect.

  final String path;

  /// Absolute resource URL on the Solid server. Folder URLs keep their
  /// trailing slash, as a Solid container requires.

  final String url;

  /// Whether this entry is a container rather than a file.

  final bool isFolder;

  /// Server-reported modification time, absent when the server does not
  /// publish one in its container listing.

  final DateTime? modified;

  /// Size in bytes, absent for folders and for servers that do not publish it.

  final int? size;

  const MediaItem({
    required this.name,
    required this.rawName,
    required this.path,
    required this.url,
    required this.isFolder,
    this.modified,
    this.size,
  });

  /// The kind of media this file holds, or null for folders and for formats
  /// PhotoPod does not display.

  MediaKind? get kind => isFolder ? null : kindOf(name);

  /// Whether this file is a still image PhotoPod can render.

  bool get isPhoto => kind == MediaKind.photo;

  /// Whether this file is a video PhotoPod can play.

  bool get isVideo => kind == MediaKind.video;

  /// A stable identity for selection tracking. The URL is unique within a Pod
  /// and survives re-sorting and re-listing.

  String get id => url;

  /// The Pod-relative path of the containing folder.

  String get parentPath {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }
}
