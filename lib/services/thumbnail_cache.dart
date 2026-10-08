/// Thumbnails for the photos and videos in the album, and EXIF details for
/// the photos.
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

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/photo_metadata.dart';
import 'package:photopod/services/media_renditions.dart';
import 'package:photopod/services/pod_media_service.dart';

/// The longest edge, in pixels, of the small rendition shown in the grid.
/// Twice the largest tile the View dialogue offers, so that it stays sharp on
/// a high density display at every tile size, and small enough that a few
/// hundred of them cost little memory.

const int thumbnailSize = 400;

/// The longest edge, in pixels, of the large rendition shown in the preview:
/// enough to fill a desktop screen, a fraction of a camera original.

const int previewSize = 2048;

/// How many photos are held in memory at once. Beyond this the least
/// recently used are dropped and rebuilt if the user scrolls back.

const int thumbnailCacheLimit = 240;

/// How many large renditions are held in memory, so that going back to a
/// photo just previewed does not fetch it again.

const int previewCacheLimit = 6;

/// How many photos are fetched from the Pod at the same time. Each one is
/// a separate round trip, and a Solid server answers a handful of concurrent
/// requests far better than a hundred.

const int thumbnailConcurrency = 4;

/// Everything the grid, the map and Get Info want to know about a photo.

class PhotoAnalysis {
  /// The small JPEG shown in the grid, or null when there is none.

  final Uint8List? thumbnail;

  /// What the photo says about itself, or null when it says nothing.

  final PhotoMetadata? metadata;

  const PhotoAnalysis({this.thumbnail, this.metadata});
}

/// Thumbnails, previews and photo details, fetched from the Pod once and then
/// kept.
///
/// Each photo has a small and a large rendition stored beside the album by
/// [MediaRenditions]. The grid, the map and Get Info read only the small one,
/// which carries the photo's EXIF details too; the preview reads the large
/// one. The original is fetched only when the user downloads it — or once,
/// for a photo added before renditions were kept, or shared by someone else,
/// in which case both renditions are made from it on the spot and, for the
/// user's own photo, stored so that the next look is quick.
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
  final Map<String, Uint8List> _previews = {};
  final Map<String, Future<PhotoAnalysis?>> _inFlight = {};
  final Map<String, Future<Uint8List?>> _previewsInFlight = {};
  final List<Completer<void>> _waiting = [];
  int _active = 0;

  /// The thumbnail and details for the photo [item] holds, or null when the
  /// file could not be read or decoded. Repeated calls for the same photo
  /// share one fetch.
  ///
  /// For a video there are no details, and the thumbnail is null when none
  /// was stored for it.

  Future<PhotoAnalysis?> analyse(MediaItem item) {
    final url = item.url;
    final cached = _touch(_analysed, url);
    if (cached != null) return Future.value(cached);

    return _inFlight.putIfAbsent(url, () async {
      await _acquire();
      try {
        final analysis = await _analyse(item);
        if (analysis != null) {
          _store(_analysed, url, analysis, thumbnailCacheLimit);
        }
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

  Future<PhotoAnalysis?> _analyse(MediaItem item) async {
    final stored = await MediaRenditions.readSmall(item);
    if (stored != null) {
      return PhotoAnalysis(thumbnail: stored.image, metadata: stored.metadata);
    }
    if (item.isVideo) return const PhotoAnalysis();

    final made = await _renderFromOriginal(item);
    if (made == null) return null;
    return PhotoAnalysis(thumbnail: made.small, metadata: made.metadata);
  }

  /// Just the thumbnail for [item].

  Future<Uint8List?> thumbnail(MediaItem item) async =>
      (await analyse(item))?.thumbnail;

  /// Just the EXIF details for [item].

  Future<PhotoMetadata?> metadata(MediaItem item) async =>
      (await analyse(item))?.metadata;

  /// The picture the preview shows for the photo [item]: its large
  /// rendition, or the original when it has none that can be made — an
  /// animated GIF, or a format that will not decode here. A TIFF original is
  /// converted, since Flutter has no codec for it.

  Future<Uint8List?> preview(MediaItem item) {
    final url = item.url;
    final cached = _touch(_previews, url);
    if (cached != null) return Future.value(cached);

    return _previewsInFlight.putIfAbsent(url, () async {
      try {
        final bytes = await _preview(item);
        if (bytes != null) _store(_previews, url, bytes, previewCacheLimit);
        return bytes;
      } finally {
        _previewsInFlight.remove(url);
      }
    });
  }

  Future<Uint8List?> _preview(MediaItem item) async {
    if (!isGif(item.name)) {
      final stored = await MediaRenditions.readLarge(item);
      if (stored != null) return stored;

      // The grid may be reading the original for this very photo right now,
      // and would leave the large rendition here when it was done.

      final pending = _inFlight[item.url];
      if (pending != null) {
        await pending;
        final made = _previews[item.url];
        if (made != null) return made;
      }

      final made = await _renderFromOriginal(item);
      if (made?.large != null) return made!.large;
    }

    final original = await PodMediaService.readBytes(item);
    if (!isTiff(item.name)) return original;
    final png = await compute(convertToPng, original);
    if (png == null) {
      throw const PodMediaException('This TIFF file could not be decoded.');
    }
    return png;
  }

  // Read the original of [item], make both renditions from it, keep the large
  // one in memory for the preview, and have them stored on the Pod for next
  // time.

  Future<PhotoRenditions?> _renderFromOriginal(MediaItem item) async {
    final original = await PodMediaService.readBytes(item);
    final made = await compute(renderPhoto, (
      bytes: original,
      keepOriginal: isGif(item.name),
    ));
    if (made == null) return null;

    final large = made.large;
    if (large != null) _store(_previews, item.url, large, previewCacheLimit);
    MediaRenditions.backfill(item, made);
    return made;
  }

  /// What is already known about [item] without going to the Pod, or null
  /// when it has not been looked at yet. The map uses this to draw the photos
  /// it already holds while the rest are still being fetched.

  PhotoAnalysis? cached(MediaItem item) => _analysed[item.url];

  /// Forget everything known about [url], so that a renamed, moved or
  /// replaced photo is fetched afresh.

  void evict(String url) {
    _analysed.remove(url);
    _previews.remove(url);
  }

  /// Forget every photo.

  void clear() {
    _analysed.clear();
    _previews.clear();
  }

  // The entry for [url], moved to the end so that the most recently used
  // entries are the last to be dropped.

  static V? _touch<V>(Map<String, V> map, String url) {
    final value = map.remove(url);
    if (value != null) map[url] = value;
    return value;
  }

  static void _store<V>(Map<String, V> map, String url, V value, int limit) {
    map.remove(url);
    map[url] = value;
    while (map.length > limit) {
      map.remove(map.keys.first);
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

/// Decode a photo's original once and make both its renditions, along with
/// whatever its EXIF block has to say. Returns null when the format cannot be
/// decoded at all.
///
/// With `keepOriginal` no large rendition is made, because the original is
/// what the preview should show: an animated GIF would stop moving.
///
/// Declared at the top level because [compute] can only run a function that
/// is not a closure.

PhotoRenditions? renderPhoto(({Uint8List bytes, bool keepOriginal}) input) {
  final decoded = _decode(input.bytes);
  if (decoded == null) return null;

  // The EXIF block is read before the orientation is baked in, since baking
  // rewrites the very tag it was read from.

  final exif = readExifMetadata(decoded);

  // Apply any EXIF rotation now, so that portrait photos taken on a phone are
  // not shown on their side.

  final upright = img.bakeOrientation(decoded);

  // JPEG has no transparency, so a large rendition of a picture that has
  // some is kept as PNG rather than have its clear parts turn black.

  final large = input.keepOriginal
      ? null
      : upright.hasAlpha
      ? img.encodePng(_fit(upright, previewSize))
      : img.encodeJpg(_fit(upright, previewSize), quality: 85);

  return PhotoRenditions(
    small: img.encodeJpg(_fit(upright, thumbnailSize), quality: 80),
    large: large,
    metadata: exif.copyWithSize(width: upright.width, height: upright.height),
  );
}

/// Decode [bytes] and produce just the grid thumbnail and the EXIF details.
/// Used for the opening frame of a video, which needs no large rendition.

PhotoAnalysis? analysePhoto(Uint8List bytes) {
  final decoded = _decode(bytes);
  if (decoded == null) return null;
  final exif = readExifMetadata(decoded);
  final upright = img.bakeOrientation(decoded);
  return PhotoAnalysis(
    thumbnail: img.encodeJpg(_fit(upright, thumbnailSize), quality: 80),
    metadata: exif.copyWithSize(width: upright.width, height: upright.height),
  );
}

// [bytes] decoded, or null when they are not a picture the `image` package
// understands — which some of its decoders report by throwing.

img.Image? _decode(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } on Object {
    return null;
  }
}

// [image] scaled down so that its longest edge is at most [size], or as it is
// when it is no bigger than that already.

img.Image _fit(img.Image image, int size) {
  final longest = image.width > image.height ? image.width : image.height;
  if (longest <= size) return image;
  return img.copyResize(
    image,
    width: image.width >= image.height ? size : null,
    height: image.height > image.width ? size : null,
    interpolation: img.Interpolation.average,
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
