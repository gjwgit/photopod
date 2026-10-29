/// Fill in the dates of photos added before PhotoPod kept them.
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

import 'package:flutter/foundation.dart';

import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/media_names.dart';
import 'package:photopod/services/thumbnail_cache.dart';

/// How many photos are looked at between two writes of the table of names,
/// so that a long backfill keeps what it has found if it is cut short.

const int _datesPerWrite = 50;

/// How many photos are looked at side by side.

const int _datesAtOnce = 4;

/// Fill in the date each of the user's photos belongs under, for photos
/// added before PhotoPod kept one.
///
/// The date is read from the EXIF details stored beside each photo's
/// thumbnail, which is one request a photo, done once: once found, it is
/// kept in [MediaNames] like the date of any photo added since. A photo with
/// no EXIF date is given the date the Pod has for it, since the time the
/// file was last changed before it was uploaded can no longer be learnt, and
/// that too is recorded so the photo is not looked at again. Videos carry no
/// EXIF, so they keep the Pod's date and cost nothing.

class MediaDatesBackfill {
  const MediaDatesBackfill._();

  // Photos already looked at this session without a date being recorded,
  // such as one that would not decode, so they are not asked for again.

  static final Set<String> _tried = <String>{};

  static Future<int>? _running;

  /// Look at those of [items] that need a date, returning how many dates
  /// were recorded. A backfill already under way is joined rather than
  /// started again.

  static Future<int> run(List<MediaItem> items) =>
      _running ??= _run(items).whenComplete(() => _running = null);

  /// Whether [item] is one the backfill would look at.

  static bool needsDate(MediaItem item) =>
      item.isPhoto &&
      !item.isShared &&
      item.taken == null &&
      !_tried.contains(item.path);

  static Future<int> _run(List<MediaItem> items) async {
    final missing = items.where(needsDate).toList();
    var recorded = 0;

    for (var start = 0; start < missing.length; start += _datesPerWrite) {
      final chunk = missing.skip(start).take(_datesPerWrite).toList();
      final found = <String, DateTime>{};

      for (var at = 0; at < chunk.length; at += _datesAtOnce) {
        final batch = chunk.skip(at).take(_datesAtOnce).toList();
        final results = await Future.wait(
          batch.map(ThumbnailCache.instance.analyse),
        );
        for (final (index, analysis) in results.indexed) {
          final item = batch[index];
          final when = analysis == null
              ? null
              : analysis.metadata?.taken ?? item.modified;
          if (when == null) {
            _tried.add(item.path);
          } else {
            found[item.path] = when;
          }
        }
      }

      if (found.isEmpty) continue;
      try {
        await MediaNames.setDates(found);
        recorded += found.length;
      } on Object catch (e) {
        debugPrint('PhotoPod: could not record the dates of photos: $e');
        return recorded;
      }
    }
    return recorded;
  }
}
