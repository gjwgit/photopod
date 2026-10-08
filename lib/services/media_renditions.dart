/// The smaller copies of each photo and video that PhotoPod keeps on the Pod,
/// so that browsing never has to fetch the originals.
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
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:solidpod/solidpod.dart';

import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/photo_metadata.dart';
import 'package:photopod/services/pod_media_service.dart';

/// The folder, at the top of the album, that holds every rendition.
///
/// The leading full stop hides it: [PodMediaService.listFolder] passes over
/// anything whose name starts with one, so the folder never shows up as one
/// of the user's own and cannot clash with a folder the user made.

const String thumbnailsFolderName = '.thumbnails';

/// The two sizes PhotoPod keeps of every photo, besides the photo itself.

enum RenditionLevel {
  /// The grid tile, at every tile size the View dialogue offers, together
  /// with what the photo's EXIF block says, so that the map and Get Info need
  /// nothing more.

  small('.small.enc.ttl'),

  /// What the preview shows: big enough to fill a screen, a fraction of the
  /// size of a photo straight off a modern camera.

  large('.large.enc.ttl');

  /// The end of the stored name, after the key that identifies the photo.

  final String suffix;

  const RenditionLevel(this.suffix);
}

/// The name the first build of video thumbnails was stored under. Each had an
/// individual key of its own; they are still read, copied and removed, so the
/// videos added back then keep their pictures.

const String _legacySuffix = '.jpg.enc.ttl';

/// The longest key a rendition name may carry. A photo buried deep enough in
/// folders to need more simply goes without, and is shown from the original,
/// rather than risk a name the server's file system will not accept.

const int _maxKeyLength = 200;

/// What a small rendition holds: the tile picture and, for a photo, its
/// details.

class SmallRendition {
  /// The JPEG shown in the grid.

  final Uint8List image;

  /// What the photo's EXIF block said, or null for a video or for a
  /// thumbnail stored before the details were kept with it.

  final PhotoMetadata? metadata;

  const SmallRendition(this.image, [this.metadata]);
}

/// Both renditions of a photo, produced together from one decode of the
/// original.

class PhotoRenditions {
  /// The grid tile, a JPEG.

  final Uint8List small;

  /// The preview, or null when the original is better shown as it is — an
  /// animated GIF, which would stop moving.

  final Uint8List? large;

  /// What the photo says about itself.

  final PhotoMetadata? metadata;

  const PhotoRenditions({required this.small, this.large, this.metadata});
}

/// The renditions of each photo and video, kept on the Pod beside the album.
///
/// Fetching and decrypting a photo straight off a camera takes far too long
/// to do for every tile, so PhotoPod stores two smaller copies of it when it
/// is added: a small one for the grid and a large one for the preview. Only
/// downloading fetches the original. A video keeps just the small one, the
/// opening frame, since playing it needs the whole file anyway.
///
/// Every rendition lives in [thumbnailsFolderName], named after the item's
/// path within the album, so that a whole folder's renditions can be found
/// and removed with a single listing when the folder is deleted. They are
/// encrypted, since a thumbnail of a private photo is every bit as private,
/// but under the one key of the folder they sit in rather than a key each:
/// solidpod rewrites its whole key file whenever a key is added, and doing
/// that twice more for every photo would make adding photos far slower.
///
/// A photo added before renditions were kept has none until it is first
/// looked at. [ThumbnailCache] then reads the original once and hands what it
/// made to [backfill], so the next look is as quick as for any other.

class MediaRenditions {
  const MediaRenditions._();

  // The folder already known to exist, so that it is only asked for once per
  // session. Kept as a URL rather than a flag so that logging in as someone
  // else checks their Pod afresh.

  static String? _ensuredFolder;
  static Future<void>? _settingUp;

  // Backfilled renditions are written one at a time, after whatever was
  // queued before them, so that browsing a folder of older photos does not
  // flood the server with writes.

  static Future<void> _queue = Future<void>.value();

  /// The small rendition of [item], or null when it has none.
  ///
  /// Something shared from someone else's Pod has none either: its
  /// renditions, if it has any, sit in its owner's album and were never
  /// shared.

  static Future<SmallRendition?> readSmall(MediaItem item) async {
    final content =
        await _read(item, RenditionLevel.small) ??
        (item.isVideo ? await _read(item, null) : null);
    if (content == null) return null;
    return decodeSmall(content);
  }

  /// The large rendition of [item], or null when it has none.

  static Future<Uint8List?> readLarge(MediaItem item) async {
    final content = await _read(item, RenditionLevel.large);
    return content == null ? null : base64Decode(content.trim());
  }

  /// Store [renditions] for the photo at Pod-relative [photoPath].

  static Future<void> savePhoto(
    String photoPath,
    PhotoRenditions renditions,
  ) async {
    await _write(
      photoPath,
      RenditionLevel.small,
      encodeSmall(renditions.small, renditions.metadata),
    );
    final large = renditions.large;
    if (large != null) {
      await _write(photoPath, RenditionLevel.large, base64Encode(large));
    }
  }

  /// Store [jpeg], the opening frame, as the thumbnail of the video at
  /// Pod-relative [videoPath].

  static Future<void> saveVideo(String videoPath, Uint8List jpeg) =>
      _write(videoPath, RenditionLevel.small, encodeSmall(jpeg));

  /// Store [renditions], made while showing the photo [item], in the
  /// background. Nothing is written for a photo that is not the user's own,
  /// or when there is no security key to encrypt with, and nothing that goes
  /// wrong is reported: the photo is simply shown from the original again
  /// next time.

  static void backfill(MediaItem item, PhotoRenditions renditions) {
    if (item.isShared) return;
    _queue = _queue.then((_) async {
      try {
        if (!await KeyManager.hasSecurityKey()) return;
        await savePhoto(item.path, renditions);
      } on Object catch (e) {
        debugPrint('PhotoPod: could not store renditions of ${item.path}: $e');
      }
    });
  }

  /// Give the item copied from [fromPath] to [toPath] the same renditions, so
  /// that a duplicated or renamed photo or video does not lose them.
  ///
  /// The renditions are only a convenience, so nothing that goes wrong here
  /// is allowed to fail the copy itself.

  static Future<void> copy(String fromPath, String toPath) async {
    try {
      final small =
          await _readPath(fromPath, RenditionLevel.small) ??
          await _readPath(fromPath, null);
      if (small != null) await _write(toPath, RenditionLevel.small, small);

      final large = await _readPath(fromPath, RenditionLevel.large);
      if (large != null) await _write(toPath, RenditionLevel.large, large);
    } on Object catch (e) {
      debugPrint('PhotoPod: could not copy the renditions of $fromPath: $e');
    }
  }

  /// Remove the renditions belonging to [items], which are being deleted:
  /// those of each photo and video, and those of everything inside each
  /// folder.
  ///
  /// The renditions folder is listed once and matched against the items, so
  /// a file that never had renditions costs nothing. Like [copy], this never
  /// fails the operation it tidies up after.

  static Future<void> forget(Iterable<MediaItem> items) async {
    final files = <String>{};
    final folders = <String>[];
    for (final item in items) {
      if (item.isShared) continue;
      if (item.isFolder) {
        folders.add('${item.path}/');
      } else {
        files.add(item.path);
      }
    }
    if (files.isEmpty && folders.isEmpty) return;

    try {
      final root = await PodMediaService.rootPath();
      final folderPath = '$root/$thumbnailsFolderName';
      if (!await PodMediaService.folderExists(
        await PodMediaService.folderUrl(folderPath),
      )) {
        return;
      }

      for (final rendition in await PodMediaService.listFolder(folderPath)) {
        if (rendition.isFolder) continue;
        final owner = _itemPathOf(root, rendition.rawName);
        if (owner == null) continue;
        if (!files.contains(owner) &&
            !folders.any((folder) => owner.startsWith(folder))) {
          continue;
        }

        try {
          // Only the first video thumbnails had a key of their own to remove
          // along with them; the rest share the folder's.

          if (rendition.rawName.endsWith(_legacySuffix)) {
            await deleteFile(fileUrl: rendition.url);
          } else {
            await deleteResource(rendition.url, ResourceContentType.any);
          }
        } on Object catch (e) {
          debugPrint('PhotoPod: could not remove a rendition of $owner: $e');
        }
      }
    } on Object catch (e) {
      debugPrint('PhotoPod: could not tidy up renditions: $e');
    }
  }

  /// The content of a small rendition holding [image] and [metadata].

  @visibleForTesting
  static String encodeSmall(Uint8List image, [PhotoMetadata? metadata]) =>
      jsonEncode({
        'version': 1,
        'image': base64Encode(image),
        if (metadata != null) 'metadata': metadata.toJson(),
      });

  /// What [encodeSmall] wrote, or a bare base64 JPEG as the first video
  /// thumbnails were stored.

  @visibleForTesting
  static SmallRendition decodeSmall(String content) {
    final trimmed = content.trim();
    if (!trimmed.startsWith('{')) {
      return SmallRendition(base64Decode(trimmed));
    }

    final json = jsonDecode(trimmed) as Map<String, dynamic>;
    final metadata = json['metadata'];
    return SmallRendition(
      base64Decode(json['image'] as String),
      metadata is Map<String, dynamic>
          ? PhotoMetadata.fromJson(metadata)
          : null,
    );
  }

  static Future<String?> _read(MediaItem item, RenditionLevel? level) async {
    if (item.isShared || item.isFolder) return null;
    return _readPath(item.path, level);
  }

  // The decrypted content of the rendition at [level] of the item at
  // [itemPath], or of its first-build thumbnail when [level] is null.

  static Future<String?> _readPath(
    String itemPath,
    RenditionLevel? level,
  ) async {
    final path = await _pathFor(itemPath, level?.suffix ?? _legacySuffix);
    if (path == null) return null;

    try {
      return await readPod(path, pathType: PathType.relativeToPod);
    } on ResourceNotExistException {
      return null;
    }
  }

  static Future<void> _write(
    String itemPath,
    RenditionLevel level,
    String content,
  ) async {
    final path = await _pathFor(itemPath, level.suffix);
    if (path == null) return;

    final folder = await _ensureFolder();

    // No access control list of its own: the rendition inherits the album's,
    // which spares a request per photo, and the encryption keeps it private.

    await writePod(
      path,
      content,
      pathType: PathType.relativeToPod,
      createAcl: false,
      overwrite: true,
      inheritKeyFrom: folder,
    );
  }

  // The Pod-relative path of the renditions folder, created if need be and
  // given the key every rendition inside it is encrypted with.
  //
  // Done once, and by a single caller however many writes arrive together:
  // two writes that each found the folder without a key would each make one,
  // and whatever the first had encrypted could not be read once the second
  // key replaced it.

  static Future<String> _ensureFolder() async {
    final root = await PodMediaService.rootPath();
    final path = '$root/$thumbnailsFolderName';
    final url = await PodMediaService.folderUrl(path);
    if (_ensuredFolder == url) return path;

    final setUp = _settingUp ??= setInheritKeyDir(
      url.endsWith('/') ? url : '$url/',
      createAcl: false,
    );
    try {
      await setUp;
      _ensuredFolder = url;
    } finally {
      if (identical(_settingUp, setUp)) _settingUp = null;
    }
    return path;
  }

  // The Pod-relative path of the rendition ending in [suffix] for the item at
  // [itemPath], or null when the item sits outside the album or too deep
  // within it.
  //
  // The key is the item's path within the album in URL-safe base64, which
  // uses only characters a resource name can carry unescaped, holds no full
  // stop, and can be decoded again to find the item a rendition belongs to.

  static Future<String?> _pathFor(String itemPath, String suffix) async {
    final root = await PodMediaService.rootPath();
    if (!itemPath.startsWith('$root/')) return null;

    final relative = itemPath.substring(root.length + 1);
    final key = base64Url.encode(utf8.encode(relative)).replaceAll('=', '');
    if (key.length > _maxKeyLength) return null;

    return '$root/$thumbnailsFolderName/$key$suffix';
  }

  // The Pod-relative path of the item whose rendition is stored as [name],
  // or null when [name] is not one of ours.

  static String? _itemPathOf(String root, String name) {
    final dot = name.indexOf('.');
    if (dot <= 0) return null;
    final suffix = name.substring(dot);
    if (suffix != _legacySuffix &&
        !RenditionLevel.values.any((level) => level.suffix == suffix)) {
      return null;
    }

    final key = name.substring(0, dot);
    try {
      return '$root/${utf8.decode(base64Url.decode(base64Url.normalize(key)))}';
    } on FormatException {
      return null;
    }
  }
}
