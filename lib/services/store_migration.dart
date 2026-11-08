/// Moving the folders an earlier build kept into the store, as albums.
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
/// Authors: Graham Williams

library;

import 'package:solidpod/solidpod.dart' show deleteItems, getFileUrl;

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/albums.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/album_sharing.dart';
import 'package:photopod/services/media_catalog.dart';
import 'package:photopod/services/media_names.dart';
import 'package:photopod/services/media_renditions.dart';
import 'package:photopod/services/media_store.dart';
import 'package:photopod/services/pod_media_service.dart';

/// What goes between the names of a folder and a folder inside it, in the
/// name of the album the inner folder becomes: `Holiday › Beach`.

const String albumPathSeparator = ' › ';

/// How many files are moved before what has been moved is recorded and the
/// originals removed.

const int _filesPerBatch = 10;

/// The name of the album the folder reached through the folders named
/// [labels] becomes.

String albumNameForFolder(List<String> labels) =>
    labels.join(albumPathSeparator);

/// Moving every photo and video an earlier build filed in folders into the
/// [MediaStore], once.
///
/// Each folder becomes an album of the same name holding what was in it, and
/// a folder inside another takes both names, `Holiday › Beach`, so nothing
/// the user organised is lost. A photo that was at the top of the album goes
/// into the store and into no album.
///
/// A photo keeps its random name, and so its thumbnails and its catalog
/// entry, both filed under that name. Only its path changes, and everyone it
/// is shared with is given the copy before the original goes. A folder is
/// removed once everything in it has moved; anything that cannot be moved,
/// or that is not a photo or a video, is left where it is, with its folder.

class StoreMigration {
  const StoreMigration._();

  /// Move everything outside the store into it, returning every move made,
  /// keyed by the old Pod-relative path, for the favourites, albums and
  /// album sharing to follow. What could not be done is added to [failed].

  static Future<Map<String, String>> run({
    required Albums albums,
    required List<String> failed,
  }) async {
    final root = await PodMediaService.rootPath();
    final moves = <String, String>{};
    await _empty(root, root, const [], albums, moves, failed);
    return moves;
  }

  // Move what is in the folder at [path], reached through the folders named
  // [labels], into the store, returning whether the folder is now empty.

  static Future<bool> _empty(
    String root,
    String path,
    List<String> labels,
    Albums albums,
    Map<String, String> moves,
    List<String> failed,
  ) async {
    final atRoot = labels.isEmpty;
    final emptied = <String>[];
    final files = <MediaItem>[];
    var keep = false;

    for (final child in await PodMediaService.listFolder(path)) {
      if (child.isFolder) {
        final label = [...labels, child.name];
        if (await _empty(root, child.path, label, albums, moves, failed)) {
          emptied.add(child.rawName);
        } else {
          keep = true;
        }
      } else if (kindOf(child.name) != null) {
        files.add(child);
      } else {
        // At the top of the album, the catalog, the favourites and the like
        // are PhotoPod's own, and stay.

        keep = keep || !atRoot;
      }
    }

    // The files are moved a few at a time, each batch finished — recorded,
    // filed and its originals removed — before the next is begun, so that a
    // migration cut short loses little and repeats little.

    for (var start = 0; start < files.length; start += _filesPerBatch) {
      final copied = <MediaItem, String>{};
      for (final file in files.skip(start).take(_filesPerBatch)) {
        try {
          copied[file] = await _copy(root, file, failed);
        } on Object catch (e) {
          failed.add('${file.name}: $e');
          keep = true;
        }
      }
      if (copied.isEmpty) continue;
      if (!await _finish(path, labels, copied, albums, moves, failed)) {
        keep = true;
      }
    }

    if (emptied.isNotEmpty) {
      final result = await deleteItems(
        parentPath: path,
        fileNames: const [],
        directoryNames: emptied,
      );
      if (result.hasFailures) keep = true;
      await MediaCatalog.forget([
        for (final name in emptied)
          if (!result.failed.containsKey(name)) '$path/$name',
      ]);
    }
    return !keep;
  }

  // Record in the catalog, and in the folder's album, where each file in
  // [copied] now is, then remove the originals from the folder at [path].
  // Returns whether every original went.

  static Future<bool> _finish(
    String path,
    List<String> labels,
    Map<MediaItem, String> copied,
    Albums albums,
    Map<String, String> moves,
    List<String> failed,
  ) async {
    final moved = {
      for (final copy in copied.entries) copy.key.path: copy.value,
    };

    // The catalog follows first, so nothing is ever in the store without its
    // name, and then the album, so nothing is ever without its folder.

    await MediaCatalog.setAll({
      for (final copy in copied.entries) copy.value: copy.key.name,
    }, moves: moved);
    if (labels.isNotEmpty &&
        !await _file(albums, albumNameForFolder(labels), moved)) {
      failed.add('The album "${albumNameForFolder(labels)}" was not saved.');
      return false;
    }

    final result = await deleteItems(
      parentPath: path,
      fileNames: [for (final item in copied.keys) item.rawName],
      directoryNames: const [],
    );
    for (final gone in result.failed.entries) {
      failed.add(
        '${gone.key} was copied but could not be removed: ${gone.value}',
      );
    }
    moves.addAll(moved);

    // An entry still under an old path belonged to a file that was given a
    // random name on the way, and now has one under that.

    await MediaCatalog.forget(moved.keys);
    return !result.hasFailures;
  }

  // Write [item] into the store, give its copy to everyone the original is
  // shared with, and return the copy's path. The original is left for the
  // caller to remove.

  static Future<String> _copy(
    String root,
    MediaItem item,
    List<String> failed,
  ) async {
    final random = isRandomStoredName(item.rawName);
    final dest = storePathOf(
      root,
      random ? item.rawName : randomStoredName(item.name),
    );
    await MediaStore.ensureShardOf(dest);

    // A copy left by a migration that was cut short is written over.

    final media = await PodMediaService.readMedia(item);
    await PodMediaService.writeMedia(
      path: dest,
      bytes: media.bytes,
      name: item.name,
      overwrite: await PodMediaService.fileExists(await getFileUrl(dest)),
    );

    // Renditions are filed under the random name, so only a file that is
    // given one here has any to move.

    if (!random) {
      await MediaRenditions.copy(item.path, dest);
      await MediaRenditions.forget([item]);
    }

    final carried = await carryAccess(item.url, await getFileUrl(dest));
    failed.addAll(carried.map((each) => '${item.name}: $each'));
    return dest;
  }

  // Put what [moved] from a folder into the album called [name], made if
  // need be. An album whose name differs only in case is the same album.

  static Future<bool> _file(
    Albums albums,
    String name,
    Map<String, String> moved,
  ) async {
    final lower = name.toLowerCase();
    final existing = albums.names.where((each) => each.toLowerCase() == lower);
    final album = existing.isEmpty ? name : existing.first;
    if (!albums.exists(album) && !await albums.create(album)) return false;
    return albums.addPaths(album, moved.values);
  }
}
