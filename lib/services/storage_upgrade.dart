/// The one-off move of everything still stored under its own name.
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

import 'package:solidpod/solidpod.dart'
    show
        PathType,
        ResourceNotExistException,
        getDataDirPath,
        getFileUrl,
        getResource,
        getWebId,
        readPod,
        writePod;

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/albums.dart';
import 'package:photopod/models/favourites.dart';
import 'package:photopod/services/album_sharing.dart';
import 'package:photopod/services/media_names.dart';
import 'package:photopod/services/media_renditions.dart';
import 'package:photopod/services/pod_keys.dart';
import 'package:photopod/services/pod_media_moves.dart';
import 'package:photopod/services/pod_media_ops.dart';
import 'package:photopod/services/pod_media_service.dart';
import 'package:photopod/services/shared_with_me.dart'
    show latestLogLines, podRootOf, sameWebId;

/// The file, hidden at the top of the album, that records how far the album
/// has been upgraded. It says nothing about the photos, so it is plain JSON.

const String storageMarkerName = '.storage.json';

/// The version of the storage layout in which nothing on the server carries
/// a name the user gave it.

const int privateStorageVersion = 2;

/// Moving an album written by an earlier build to the private layout.
///
/// Until random names, every photo, video and folder was stored under the
/// name the user gave it, every album under the album's name, and every
/// rendition under its item's path, so anyone who could see the server —
/// its administrator, say — could read `background_pinnacles_winter_2026_
/// with_fred_and_simon.jpg` straight off it. This moves all of it to random
/// names, once, carrying along each item's name, renditions, hearts, places
/// in albums, and everyone it is shared with:
///
/// 1. albums are moved to random file names, with their names inside;
/// 2. folders and files are moved to random names; see [PodMediaMoves];
/// 3. the hearts, albums and record of album sharing follow the moves;
/// 4. shared files written before names were kept inside files are given
///    their names, so their recipients see them;
/// 5. renditions still filed under their item's path are refiled.
///
/// Anything that cannot be done is reported and left as it was, and the
/// whole upgrade is tried again next time, skipping what is already done.

class StorageUpgrade {
  const StorageUpgrade._();

  static bool _done = false;
  static Future<List<String>>? _running;

  /// Whether the album still needs upgrading. Asks the Pod at most until the
  /// answer is no.

  static Future<bool> isNeeded() async {
    if (_done) return false;
    try {
      final path = await _markerPath();
      if (await PodMediaService.fileExists(await getFileUrl(path))) {
        final content = await readPod(path, pathType: PathType.relativeToPod);
        final decoded = jsonDecode(content);
        if (decoded is Map && (decoded['version'] as int? ?? 0) >= 2) {
          _done = true;
          MediaRenditions.refiled = true;
          return false;
        }
      }
    } on Object catch (e) {
      debugPrint('PhotoPod: could not read the storage marker: $e');
    }
    return true;
  }

  /// Upgrade the album, returning what could not be done. Callers arriving
  /// while an upgrade is running wait for that one. The security key must be
  /// in hand.

  static Future<List<String>> run({
    required Favourites favourites,
    required Albums albums,
    required AlbumSharing sharing,
  }) => _running ??= _run(
    favourites,
    albums,
    sharing,
  ).whenComplete(() => _running = null);

  static Future<List<String>> _run(
    Favourites favourites,
    Albums albums,
    AlbumSharing sharing,
  ) async {
    await PodKeys.unlocked();
    MediaNames.invalidate();
    await MediaNames.ensureLoaded();
    await favourites.load();
    await albums.load();
    await sharing.load();

    final failed = <String>[];

    // The renditions of files that already have random names are refiled
    // first, so that they need not be copied when their folder moves.

    await MediaRenditions.refileByPath(removeOthers: false);

    // 1. The albums, whose recipients are given the new file before the old
    // one goes.

    failed.addAll(
      await albums.moveToRandomNames(
        (name, url) => sharing.carryAlbumFiles({name: url}),
      ),
    );

    // 2 and 3. Everything in the album, and what refers to it.

    final moves = <String, String>{};
    await _walk(await PodMediaService.rootPath(), moves, failed, atRoot: true);
    if (moves.isNotEmpty) {
      await favourites.retarget(moves);
      await albums.retarget(moves);
      await sharing.retarget(moves);
    }

    // 4. Shared files that do not carry their names. The ones just moved
    // were written with them.

    for (final path in await _sharedPaths(sharing)) {
      if (_movedWith(path, moves)) continue;
      final stored = path.substring(path.lastIndexOf('/') + 1);
      if (!isRandomStoredName(stored)) continue;
      if (kindOf(displayNameOf(stored)) == null) continue;
      try {
        await PodMediaOps.ensureNameInside(path);
      } on ResourceNotExistException {
        // Shared once, and deleted since.
      } on Object catch (e) {
        failed.add('${MediaNames.nameOf(path) ?? stored}: $e');
      }
    }

    // 5. The renditions, now that every item has the name it will keep.

    final unfiled = await MediaRenditions.refileByPath();
    if (unfiled > 0) {
      failed.add('$unfiled thumbnails could not be refiled.');
    } else {
      MediaRenditions.refiled = true;
    }

    if (failed.isEmpty) {
      await writePod(
        await _markerPath(),
        jsonEncode({'version': privateStorageVersion}),
        encrypted: false,
        createAcl: false,
        overwrite: true,
        pathType: PathType.relativeToPod,
      );
      _done = true;
    }
    return failed;
  }

  // Move every folder and file under [podPath] that is stored under its own
  // name. A folder that moves takes everything in it along; one that keeps
  // its random name is looked into. At the top of the album, PhotoPod's own
  // bookkeeping files are left alone, as is anything that is not a photo or
  // a video.

  static Future<void> _walk(
    String podPath,
    Map<String, String> moves,
    List<String> failed, {
    bool atRoot = false,
  }) async {
    for (final child in await PodMediaService.listFolder(podPath)) {
      try {
        if (child.isFolder) {
          if (isRandomFolderName(child.rawName)) {
            await _walk(child.path, moves, failed);
          } else {
            moves.addAll(
              await PodMediaMoves.moveFolder(child, failures: failed),
            );
          }
          continue;
        }
        if (kindOf(child.name) == null || isRandomStoredName(child.rawName)) {
          continue;
        }
        moves[child.path] = await PodMediaMoves.moveFile(
          child,
          failures: failed,
        );
      } on Object catch (e) {
        failed.add('${child.name}: $e');
      }
    }
  }

  // The Pod-relative paths of the user's own files that are shared: those
  // album sharing gave access to, and those the user's permission log says
  // were shared directly.

  static Future<Set<String>> _sharedPaths(AlbumSharing sharing) async {
    final paths = {...sharing.grantedPaths};
    try {
      final me = await getWebId();
      final dataDir = await getDataDirPath();
      final app = dataDir.split('/').first;
      final log = await getFileUrl('$app/logs/permissions-log.ttl');
      final content = utf8.decode(await getResource(log));
      for (final line in latestLogLines(content).values) {
        if (line.type != 'grant' || me == null) continue;
        if (sameWebId(line.owner) != sameWebId(me)) continue;
        final root = podRootOf(line.url, dataDir);
        if (root != null) paths.add(line.url.substring(root.length));
      }
    } on Object catch (e) {
      debugPrint('PhotoPod: could not read what you have shared: $e');
    }
    return paths;
  }

  // Whether [path], or a folder it is in, was moved, in which case it was
  // written again with its name inside.

  static bool _movedWith(String path, Map<String, String> moves) =>
      moves.keys.any((old) => path == old || path.startsWith('$old/'));

  static Future<String> _markerPath() async =>
      '${await getDataDirPath()}/$storageMarkerName';
}
