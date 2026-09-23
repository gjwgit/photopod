/// Thumbnails and EXIF details for the photos in the album.
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
import 'package:photopod/models/photo_metadata.dart';
import 'package:photopod/services/pod_media_service.dart';

/// The longest edge, in pixels, of a generated thumbnail. Large enough to
/// stay sharp on a high density display at the grid's tile size, small
/// enough that a few hundred of them cost little memory.

const int thumbnailSize = 320;

/// How many photos are held in memory at once. Beyond this the least
/// recently used are dropped and rebuilt if the user scrolls back.

const int thumbnailCacheLimit = 240;

/// How many photos are fetched from the Pod at the same time. Each one is
/// a separate round trip, and a Solid server answers a handful of concurrent
/// requests far better than a hundred.

const int thumbnailConcurrency = 4;

/// Everything one pass over a photo's bytes yields.
///
/// The thumbnail and the EXIF block are produced together because both need
/// the photo decoded, and the photo has to be fetched from the Pod and
/// decrypted before it can be decoded at all. Reading the details for the Get
/// Info panel or for the map therefore costs nothing once the grid has shown
/// the photo, and showing the grid costs nothing once the map has been drawn.

class PhotoAnalysis {
  /// The downscaled JPEG shown in the grid, or null when the format could not
  /// be decoded.

  final Uint8List? thumbnail;

  /// What the photo says about itself, or null when it says nothing.

  final PhotoMetadata? metadata;

  const PhotoAnalysis({this.thumbnail, this.metadata});
}

/// Thumbnails and photo details, fetched from the Pod once and then kept.
///
/// Decoding happens on a background isolate through [compute], which matters
/// because the `image` package is pure Dart and a full size photo would
/// otherwise stall the frame. It also gives PhotoPod TIFF support, which
/// Flutter's own codecs do not provide.

class ThumbnailCache {
  ThumbnailCache._();

  /// The single cache shared by every browser view.

  static final ThumbnailCache instance = ThumbnailCache._();

  final Map<String, PhotoAnalysis> _analysed = {};
  final Map<String, Future<PhotoAnalysis?>> _inFlight = {};
  final List<Completer<void>> _waiting = [];
  int _active = 0;

  /// The thumbnail and details for the photo [item] holds, or null when the
  /// file could not be read or decoded. Repeated calls for the same photo
  /// share one fetch.

  Future<PhotoAnalysis?> analyse(MediaItem item) {
    final url = item.url;
    final cached = _analysed.remove(url);
    if (cached != null) {
      // Reinsert so the most recently used entry sits at the end.

      _analysed[url] = cached;
      return Future.value(cached);
    }

    return _inFlight.putIfAbsent(url, () async {
      await _acquire();
      try {
        final bytes = await PodMediaService.readBytes(item);
        final analysis = await compute(analysePhoto, bytes);
        if (analysis != null) _store(url, analysis);
        return analysis;
      } on Object catch (e) {
        debugPrint('PhotoPod: could not read $url: $e');
        return null;
      } finally {
        _release();
        _inFlight.remove(url);
      }
    });
  }

  /// Just the thumbnail for [item].

  Future<Uint8List?> thumbnail(MediaItem item) async =>
      (await analyse(item))?.thumbnail;

  /// Just the EXIF details for [item].

  Future<PhotoMetadata?> metadata(MediaItem item) async =>
      (await analyse(item))?.metadata;

  /// What is already known about [item] without going to the Pod, or null
  /// when it has not been looked at yet. The map uses this to draw the photos
  /// it already holds while the rest are still being fetched.

  PhotoAnalysis? cached(MediaItem item) => _analysed[item.url];

  /// Forget everything known about [url], so that a renamed, moved or
  /// replaced photo is fetched afresh.

  void evict(String url) => _analysed.remove(url);

  /// Forget every photo.

  void clear() => _analysed.clear();

  void _store(String url, PhotoAnalysis analysis) {
    _analysed[url] = analysis;
    while (_analysed.length > thumbnailCacheLimit) {
      _analysed.remove(_analysed.keys.first);
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

/// Decode [bytes] once, producing both the grid thumbnail and whatever the
/// photo's EXIF block has to say. Returns null when the format cannot be
/// decoded at all.
///
/// Declared at the top level because [compute] can only run a function that
/// is not a closure.

PhotoAnalysis? analysePhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  // The EXIF block is read before the orientation is baked in, since baking
  // rewrites the very tag it was read from.

  final exif = readExifMetadata(decoded);

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

  return PhotoAnalysis(
    thumbnail: img.encodeJpg(resized, quality: 80),
    metadata: exif.copyWithSize(width: upright.width, height: upright.height),
  );
}

/// Pull the tags PhotoPod shows out of a decoded [image].
///
/// Everything is optional: a PNG straight out of a screenshot tool carries no
/// EXIF at all, and cameras differ over which tags they bother to write.

PhotoMetadata readExifMetadata(img.Image image) {
  final exif = image.exif;
  if (exif.isEmpty) return const PhotoMetadata();

  final ifd0 = exif.imageIfd;
  final sub = exif.exifIfd;
  final gps = exif.gpsIfd;

  return PhotoMetadata(
    taken: parseExifDateTime(
      _text(sub['DateTimeOriginal']) ?? _text(ifd0['DateTime']),
    ),
    cameraMake: _text(ifd0['Make']),
    cameraModel: _text(ifd0['Model']),
    lens: _text(sub['LensModel']),
    exposureSeconds: _positive(sub['ExposureTime']),
    aperture: _positive(sub['FNumber']),
    focalLength: _positive(sub['FocalLength']),
    iso: _positive(sub['ISOSpeed'])?.round(),
    latitude: _coordinate(gps, 'GPSLatitude', 'GPSLatitudeRef', limit: 90),
    longitude: _coordinate(gps, 'GPSLongitude', 'GPSLongitudeRef', limit: 180),
    altitude: _altitude(gps),
  );
}

// A trimmed string, or null when the tag is missing or holds only padding.
// EXIF ascii values are commonly padded out to a fixed width with NULs.

String? _text(img.IfdValue? value) {
  final text = value?.toString().replaceAll(String.fromCharCode(0), '').trim();
  return text == null || text.isEmpty ? null : text;
}

double? _positive(img.IfdValue? value) {
  if (value == null) return null;
  final number = value.toDouble();
  return number.isFinite && number > 0 ? number : null;
}

// GPS coordinates are written as three rationals - degrees, minutes and
// seconds - with the hemisphere in a separate tag.

double? _coordinate(
  img.IfdDirectory gps,
  String tag,
  String refTag, {
  required double limit,
}) {
  final value = gps[tag];
  if (value == null || value.length < 3) return null;

  return dmsToDegrees(
    value.toDouble(0),
    value.toDouble(1),
    value.toDouble(2),
    _text(gps[refTag]),
    limit: limit,
  );
}

// Altitude comes as a positive rational with a separate tag saying whether it
// is above sea level (0) or below it (1).

double? _altitude(img.IfdDirectory gps) {
  final value = gps['GPSAltitude'];
  if (value == null) return null;

  final metres = value.toDouble();
  if (!metres.isFinite || metres == 0) return null;
  return gps['GPSAltitudeRef']?.toInt() == 1 ? -metres : metres;
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
