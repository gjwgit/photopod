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

/// The seven ways PhotoPod offers to look at an album, one per entry in the
/// navigation rail down the left hand side.
///
/// Every section is a view over the whole album at once, read from the
/// album index: everything, two filters, the albums, the people in the
/// photos, the tags on them and a map.

enum LibrarySection {
  /// Every photo and video in the album, and everything shared with the
  /// user, as a timeline.

  library('Library', Icons.photo_library_outlined),

  /// Every favourited photo and video in the album, whichever folder it is
  /// filed under.

  favourites('Favourites', Icons.favorite_outline),

  /// Every album the user has made, with Favourites first, each one opening
  /// out into a row of its photos and videos.

  albums('Albums', Icons.photo_album_outlined),

  /// Everyone whose face turns up in the album, each with the photos they
  /// are in, found by the PhotoPod Analyser.

  people('People', Icons.face_outlined),

  /// Every tag on the photos in the album, such as Beach or Dog, each with
  /// the photos that carry it, worked out by the PhotoPod Analyser.

  tags('Tags', Icons.sell_outlined),

  /// Every video in the album, whichever folder it is filed under.

  videos('Videos', Icons.movie_outlined),

  /// The photos that carry GPS coordinates, shown where they were taken.

  maps('Maps', Icons.map_outlined);

  /// Label shown in the navigation rail and in dialogue titles.

  final String label;

  /// Icon shown in the navigation rail.

  final IconData icon;

  const LibrarySection(this.label, this.icon);

  /// Whether photos and videos can be added from this section.

  bool get acceptsUploads => this == LibrarySection.library;

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
    LibrarySection.albums => 'albums',
    LibrarySection.people => 'people',
    LibrarySection.tags => 'tags',
    LibrarySection.videos => 'videos',
    LibrarySection.maps => 'places',
  };
}
