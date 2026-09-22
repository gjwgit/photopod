/// Build and cache photo thumbnails.
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

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:image/image.dart' as img;

import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/pod_media_service.dart';

/// The longest edge, in pixels, of a generated thumbnail. Large enough to
/// stay sharp on a high density display at the grid's tile size, small
/// enough that a few hundred of them cost little memory.

const int thumbnailSize = 320;

/// How many thumbnails are held in memory at once. Beyond this the least
/// recently used are dropped and rebuilt if the user scrolls back.

const int thumbnailCacheLimit = 240;

/// How many thumbnails are fetched from the Pod at the same time. Each one is
/// a separate round trip, and a Solid server answers a handful of concurrent
/// requests far better than a hundred.

const int thumbnailConcurrency = 4;

/// Thumbnails for the photo grid, fetched from the Pod once and then kept.
///
/// Decoding happens on a background isolate through [compute], which matters
/// because the `image` package is pure Dart and a full size photo would
/// otherwise stall the frame. It also gives PhotoPod TIFF support, which
/// Flutter's own codecs do not provide.

class ThumbnailCache {
  ThumbnailCache._();

  /// The single cache shared by every browser view.

  static final ThumbnailCache instance = ThumbnailCache._();

  final Map<String, Uint8List> _thumbnails = {};
  final Map<String, Future<Uint8List?>> _inFlight = {};
  final List<Completer<void>> _waiting = [];
  int _active = 0;

  /// The thumbnail for the photo [item] holds, or null when the file could
  /// not be read or decoded. Repeated calls for the same photo share one
  /// fetch.

  Future<Uint8List?> thumbnail(MediaItem item) {
    final url = item.url;
    final cached = _thumbnails.remove(url);
    if (cached != null) {
      // Reinsert so the most recently used entry sits at the end.

      _thumbnails[url] = cached;
      return Future.value(cached);
    }

    return _inFlight.putIfAbsent(url, () async {
      await _acquire();
      try {
        final bytes = await PodMediaService.readBytes(item);
        final thumb = await compute(buildThumbnail, bytes);
        if (thumb != null) _store(url, thumb);
        return thumb;
      } on Object catch (e) {
        debugPrint('PhotoPod: no thumbnail for $url: $e');
        return null;
      } finally {
        _release();
        _inFlight.remove(url);
      }
    });
  }

  /// Forget the thumbnail for [url], so that a renamed, moved or replaced
  /// photo is fetched afresh.

  void evict(String url) => _thumbnails.remove(url);

  /// Forget every thumbnail.

  void clear() => _thumbnails.clear();

  void _store(String url, Uint8List bytes) {
    _thumbnails[url] = bytes;
    while (_thumbnails.length > thumbnailCacheLimit) {
      _thumbnails.remove(_thumbnails.keys.first);
    }
  }

  Future<void> _acquire() async {
    if (_active < thumbnailConcurrency) {
      _active++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
      return;
    }
    _active--;
  }
}

/// Decode [bytes] and shrink the image to [thumbnailSize] on its longest
/// edge, returning JPEG bytes, or null when the format cannot be decoded.
///
/// Declared at the top level because [compute] can only run a function that
/// is not a closure.

Uint8List? buildThumbnail(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  // Apply any EXIF rotation now, so that portrait photos taken on a phone are
  // not shown on their side.

  final upright = img.bakeOrientation(decoded);
  final longest = upright.width > upright.height
      ? upright.width
      : upright.height;

  final resized = longest <= thumbnailSize
      ? upright
      : img.copyResize(
          upright,
          width: upright.width >= upright.height ? thumbnailSize : null,
          height: upright.height > upright.width ? thumbnailSize : null,
          interpolation: img.Interpolation.average,
        );

  return img.encodeJpg(resized, quality: 80);
}

/// Re-encode [bytes] as PNG so that Flutter can display them.
///
/// Only needed for TIFF, which has no Flutter codec. Everything else PhotoPod
/// supports is handed to `Image.memory` untouched, which keeps animated GIFs
/// animating and avoids a pointless decode of a format the engine already
/// understands. Returns null when the bytes cannot be decoded.

Uint8List? convertToPng(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return img.encodePng(img.bakeOrientation(decoded));
}
