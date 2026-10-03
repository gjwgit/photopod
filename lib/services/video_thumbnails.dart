/// The stored thumbnails that stand in for videos in the grid.
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

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:solidpod/solidpod.dart';

import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/pod_media_service.dart';

/// The folder, at the top of the album, that holds every video thumbnail.
///
/// The leading full stop hides it: [PodMediaService.listFolder] passes over
/// anything whose name starts with one, so the folder never shows up as one
/// of the user's own and cannot clash with a folder the user made.

const String thumbnailsFolderName = '.thumbnails';

/// The name a thumbnail is stored under, after the key that identifies its
/// video. It is encrypted, like the video itself, since a frame of a private
/// video is every bit as private.

const String _thumbnailSuffix = '.jpg.enc.ttl';

/// The longest key a thumbnail name may carry. A video buried deep enough in
/// folders to need more simply goes without a thumbnail, rather than risk a
/// name the server's file system will not accept.

const int _maxKeyLength = 200;

/// The first frame of each video, captured when the video was added and kept
/// on the Pod beside the album.
///
/// Pulling a frame out of a video means fetching, decrypting and decoding the
/// whole file, which is far too slow to do for every tile in a folder of
/// videos. The frame is therefore captured once, when the video is added and
/// its bytes are already in hand, and stored as a small JPEG that costs no
/// more to show than a photo's thumbnail.
///
/// Every thumbnail lives in [thumbnailsFolderName], named after the video's
/// path within the album, so that a whole folder's thumbnails can be found
/// and removed with a single listing when the folder is deleted. A video
/// added before thumbnails were captured, or one whose frame could not be
/// read, has none, and the grid shows a film glyph for it as before.

class VideoThumbnails {
  const VideoThumbnails._();

  // The thumbnails folder already known to exist, so that it is only asked
  // for once per session. Kept as a URL rather than a flag so that logging in
  // as someone else checks their Pod afresh.

  static String? _ensuredFolder;

  /// The thumbnail captured for [item], or null when it has none.
  ///
  /// A video shared from someone else's Pod has none either: its thumbnail,
  /// if there is one, sits in its owner's album and was never shared.

  static Future<Uint8List?> read(MediaItem item) async {
    if (item.isShared || !item.isVideo) return null;

    final path = await _pathFor(item.path);
    if (path == null) return null;

    try {
      final content = await readPod(path, pathType: PathType.relativeToPod);
      return base64Decode(content.trim());
    } on ResourceNotExistException {
      return null;
    }
  }

  /// Store [jpeg] as the thumbnail of the video at Pod-relative [videoPath],
  /// replacing any thumbnail it already had.

  static Future<void> save(String videoPath, Uint8List jpeg) async {
    final path = await _pathFor(videoPath);
    if (path == null) return;

    await _ensureFolder();

    // No access control list of its own: the thumbnail inherits the album's,
    // which spares a request per video, and the encryption keeps it private.

    await writePod(
      path,
      base64Encode(jpeg),
      pathType: PathType.relativeToPod,
      createAcl: false,
      overwrite: true,
    );
  }

  /// Give the video copied from [fromPath] to [toPath] the same thumbnail,
  /// so that a duplicated or renamed video does not lose its picture.
  ///
  /// The thumbnail is only a convenience, so nothing that goes wrong here is
  /// allowed to fail the copy itself.

  static Future<void> copy(String fromPath, String toPath) async {
    try {
      final from = await _pathFor(fromPath);
      if (from == null) return;

      final String content;
      try {
        content = await readPod(from, pathType: PathType.relativeToPod);
      } on ResourceNotExistException {
        return;
      }
      await save(toPath, base64Decode(content.trim()));
    } on Object catch (e) {
      debugPrint('PhotoPod: could not copy the thumbnail of $fromPath: $e');
    }
  }

  /// Remove the thumbnails belonging to [items], which are being deleted: the
  /// thumbnail of each video, and those of every video inside each folder.
  ///
  /// The thumbnails folder is listed once and matched against the items, so
  /// a video that never had a thumbnail costs nothing. Like [copy], this
  /// never fails the operation it tidies up after.

  static Future<void> forget(Iterable<MediaItem> items) async {
    final files = <String>{};
    final folders = <String>[];
    for (final item in items) {
      if (item.isShared) continue;
      if (item.isFolder) {
        folders.add('${item.path}/');
      } else if (item.isVideo) {
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

      for (final thumbnail in await PodMediaService.listFolder(folderPath)) {
        if (thumbnail.isFolder) continue;
        final video = _videoPathOf(root, thumbnail.rawName);
        if (video == null) continue;
        if (!files.contains(video) &&
            !folders.any((folder) => video.startsWith(folder))) {
          continue;
        }

        try {
          await deleteFile(fileUrl: thumbnail.url);
        } on Object catch (e) {
          debugPrint('PhotoPod: could not remove the thumbnail of $video: $e');
        }
      }
    } on Object catch (e) {
      debugPrint('PhotoPod: could not tidy up video thumbnails: $e');
    }
  }

  static Future<void> _ensureFolder() async {
    final root = await PodMediaService.rootPath();
    final url = await PodMediaService.folderUrl('$root/$thumbnailsFolderName');
    if (_ensuredFolder == url) return;
    await PodMediaService.ensureFolder(url);
    _ensuredFolder = url;
  }

  // The Pod-relative path of the thumbnail for the video at [videoPath], or
  // null when the video sits outside the album or too deep within it.
  //
  // The key is the video's path within the album in URL-safe base64, which
  // uses only characters a resource name can carry unescaped, and which can
  // be decoded again to find the video a thumbnail belongs to.

  static Future<String?> _pathFor(String videoPath) async {
    final root = await PodMediaService.rootPath();
    if (!videoPath.startsWith('$root/')) return null;

    final relative = videoPath.substring(root.length + 1);
    final key = base64Url.encode(utf8.encode(relative)).replaceAll('=', '');
    if (key.length > _maxKeyLength) return null;

    return '$root/$thumbnailsFolderName/$key$_thumbnailSuffix';
  }

  // The Pod-relative path of the video whose thumbnail is stored as [name],
  // or null when [name] is not one of ours.

  static String? _videoPathOf(String root, String name) {
    if (!name.endsWith(_thumbnailSuffix)) return null;
    final key = name.substring(0, name.length - _thumbnailSuffix.length);
    try {
      return '$root/${utf8.decode(base64Url.decode(base64Url.normalize(key)))}';
    } on FormatException {
      return null;
    }
  }
}
