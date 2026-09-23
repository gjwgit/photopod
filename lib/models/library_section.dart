/// The sections the album is presented in.
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

import 'package:photopod/constants/media.dart';

/// The four ways PhotoPod offers to look at an album, one per entry in the
/// navigation rail down the left hand side.
///
/// Only [library] browses the folders the media actually sits in. The other
/// three are views over the whole album at once: two filters and a map. They
/// therefore read from the album index rather than from a single container
/// listing, and none of them shows a folder.

enum LibrarySection {
  /// Every photo and video in the folder being looked at, mixed together as
  /// tiles, with the subfolders alongside them.

  library('Library', Icons.photo_library_outlined),

  /// Every favourited photo and video in the album, whichever folder it is
  /// filed under.

  favourites('Favourites', Icons.favorite_outline),

  /// Every video in the album, whichever folder it is filed under.

  videos('Videos', Icons.movie_outlined),

  /// The photos that carry GPS coordinates, shown where they were taken.

  maps('Maps', Icons.map_outlined);

  /// Label shown in the navigation rail and in dialogue titles.

  final String label;

  /// Icon shown in the navigation rail.

  final IconData icon;

  const LibrarySection(this.label, this.icon);

  /// Whether this section browses folders, rather than presenting the album
  /// as one flat collection.

  bool get browsesFolders => this == LibrarySection.library;

  /// Whether this section is one of the two tiled lists of files.

  bool get isFlatList =>
      this == LibrarySection.favourites || this == LibrarySection.videos;

  /// The kinds of media this section puts on screen.

  Set<MediaKind> get kinds => this == LibrarySection.videos
      ? const {MediaKind.video}
      : const {MediaKind.photo, MediaKind.video};

  /// The plural noun for what this section holds, used in messages.

  String get noun => switch (this) {
    LibrarySection.library => 'photos and videos',
    LibrarySection.favourites => 'favourites',
    LibrarySection.videos => 'videos',
    LibrarySection.maps => 'places',
  };
}
