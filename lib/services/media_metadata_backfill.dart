/// Fill in the EXIF details, and so the dates, of photos added before the
/// catalog kept them.
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
/// Authors: Tony Chen, Graham Williams

library;

import 'package:flutter/foundation.dart';

import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/photo_metadata.dart';
import 'package:photopod/services/demo_library.dart';
import 'package:photopod/services/media_catalog.dart';
import 'package:photopod/services/thumbnail_cache.dart';

/// How many photos are looked at between two writes of the catalog, so that
/// a long backfill keeps what it has found if it is cut short.

const int _photosPerWrite = 50;

/// How many photos are looked at side by side.

const int _photosAtOnce = 4;

/// Fill in what each of the user's photos says about itself, for photos
/// added before the catalog kept it.
///
/// The details are read from the EXIF block stored beside each photo's
/// thumbnail, which is one request a photo, done once: once found, they are
/// kept in [MediaCatalog] like those of any photo added since, and the map
/// and the timeline read them from there. A photo with no EXIF date is given
/// the date the Pod has for it, since the time the file was last changed
/// before it was uploaded can no longer be learnt. Videos carry no EXIF, so
/// they keep the Pod's date and cost nothing.

class MediaMetadataBackfill {
  const MediaMetadataBackfill._();

  // Photos already looked at this session without anything being recorded,
  // such as one that would not decode, so they are not asked for again.

  static final Set<String> _tried = <String>{};

  static Future<int>? _running;

  /// Look at those of [items] that need their details, returning how many
  /// were recorded. A backfill already under way is joined rather than
  /// started again.

  static Future<int> run(List<MediaItem> items) =>
      _running ??= _run(items).whenComplete(() => _running = null);

  /// Whether [item] is one the backfill would look at.

  static bool needsDetails(MediaItem item) =>
      item.isPhoto &&
      !item.isShared &&
      !DemoLibrary.isDemo(item) &&
      MediaCatalog.metadataOf(item.path) == null &&
      !_tried.contains(item.path);

  static Future<int> _run(List<MediaItem> items) async {
    final missing = items.where(needsDetails).toList();
    var recorded = 0;

    for (var start = 0; start < missing.length; start += _photosPerWrite) {
      final chunk = missing.skip(start).take(_photosPerWrite).toList();
      final found = <String, PhotoMetadata>{};
      final dates = <String, DateTime>{};

      for (var at = 0; at < chunk.length; at += _photosAtOnce) {
        final batch = chunk.skip(at).take(_photosAtOnce).toList();
        final results = await Future.wait(
          batch.map(ThumbnailCache.instance.analyse),
        );
        for (final (index, analysis) in results.indexed) {
          final item = batch[index];
          if (analysis == null) {
            _tried.add(item.path);
            continue;
          }

          // A photo that says nothing is recorded as saying nothing, so it
          // is not looked at again.

          found[item.path] = analysis.metadata ?? const PhotoMetadata();
          final modified = item.modified;
          if (modified != null) dates[item.path] = modified;
        }
      }

      if (found.isEmpty) continue;
      try {
        await MediaCatalog.setMetadata(found, dates: dates);
        recorded += found.length;
      } on Object catch (e) {
        debugPrint('PhotoPod: could not record the details of photos: $e');
        return recorded;
      }
    }
    return recorded;
  }
}
