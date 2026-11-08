/// Duplicate, rename and delete media in the Pod.
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

import 'package:solidpod/solidpod.dart';

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/media_catalog.dart';
import 'package:photopod/services/media_envelope.dart';
import 'package:photopod/services/media_names.dart';
import 'package:photopod/services/media_renditions.dart';
import 'package:photopod/services/media_store.dart';
import 'package:photopod/services/pod_media_moves.dart';
import 'package:photopod/services/pod_media_service.dart';

/// The operations the toolbar performs on whole items rather than on bytes.
///
/// Solid has no server-side copy or rename. A file is stored under a random
/// name and known to the user by the name kept inside it and in
/// [MediaCatalog], so renaming a file rewrites it in place. A copy is a read
/// and a write, into the [MediaStore].

class PodMediaOps {
  const PodMediaOps._();

  /// Make a copy of each of [items] in the store, returning the
  /// Pod-relative path of every copy keyed by the path it was copied from.
  ///
  /// The copy is named after the original with `_copy` before the extension,
  /// or `_copy_1`, `_copy_2` and so on when that is taken by anything in the
  /// catalog, so that nothing is ever confused with the original. Folders are
  /// left out: a duplicate is a photo or a video.

  static Future<Map<String, String>> duplicateAll(List<MediaItem> items) async {
    final copies = <String, String>{};
    final names = {for (final entry in MediaCatalog.entries) ?entry.name};

    for (final item in items) {
      if (item.isFolder) continue;
      final name = duplicateName(item.name, names);
      copies[item.path] = await _copyFile(item, name);
      names.add(name);
    }
    return copies;
  }

  /// The name a duplicate of [name] takes, given the names already [taken] in
  /// its folder: `beach_copy.jpg`, then `beach_copy_1.jpg`, `beach_copy_2.jpg`
  /// and so on, the first that is free.

  static String duplicateName(String name, Set<String> taken) {
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    final extension = dot <= 0 ? '' : name.substring(dot);

    final first = '${stem}_copy$extension';
    if (!taken.contains(first)) return first;

    for (var n = 1; ; n++) {
      final candidate = '${stem}_copy_$n$extension';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  /// Rename [item] to [newName], returning every move that made, keyed by
  /// the old Pod-relative path: nothing, when the item kept its path.
  ///
  /// Every item is stored under a random name, so two may share the name the
  /// user gives them. A file or folder stored under a random name keeps it:
  /// the new name is written into [MediaCatalog], and for a file into the
  /// file itself, which is what lets everyone it is shared with see it. One
  /// still stored under the name it was added with is moved to a random name
  /// instead; see [PodMediaMoves].

  static Future<Map<String, String>> rename(
    MediaItem item,
    String newName,
  ) async {
    if (item.isFolder) {
      if (!isRandomFolderName(item.rawName)) {
        return PodMediaMoves.moveFolder(item, name: newName);
      }
      await MediaCatalog.set(item.path, newName);
      return const {};
    }

    if (!isRandomStoredName(item.rawName)) {
      return {item.path: await PodMediaMoves.moveFile(item, name: newName)};
    }

    // The file is written again with the new name in it, under the key it
    // already has, so that everyone it is shared with can still read it.

    final bytes = await PodMediaService.readBytes(item);
    await PodMediaService.writeMedia(
      path: item.path,
      bytes: bytes,
      name: newName,
      overwrite: true,
    );
    await MediaCatalog.set(item.path, newName);
    return const {};
  }

  /// Make sure the file at Pod-relative [path] carries its name inside it,
  /// as everything written before names were kept there does not, so that
  /// whoever it is about to be shared with sees the name rather than the
  /// random one it is stored under.

  static Future<void> ensureNameInside(String path) async {
    final content = await readPod(path, pathType: PathType.relativeToPod);
    final media = decodeMedia(content);
    if (media.name != null) return;

    final stored = path.substring(path.lastIndexOf('/') + 1);
    await PodMediaService.writeMedia(
      path: path,
      bytes: media.bytes,
      name: MediaCatalog.nameOf(path) ?? displayNameOf(stored),
      overwrite: true,
    );
  }

  /// Delete [items], which all sit in [parentPodPath]. Folders are removed
  /// with everything inside them, and so are the renditions and the names of
  /// everything that went.

  static Future<BatchDeleteResult> deleteAll(
    String parentPodPath,
    List<MediaItem> items,
  ) async {
    // The renditions of a file are filed under its own random name rather
    // than its folder, so what is inside each folder is found while it is
    // still there to be listed.

    final inside = <String>[];
    for (final item in items) {
      if (item.isFolder && !item.isShared) {
        inside.addAll(await filesUnder(item));
      }
    }

    final names = storedNamesOf(items);
    final result = await deleteItems(
      parentPath: parentPodPath,
      fileNames: names.files,
      directoryNames: names.folders,
    );
    final gone = items
        .where((item) => !result.failed.containsKey(item.rawName))
        .toList();
    await MediaRenditions.forget(gone, inside: inside);
    await MediaCatalog.forget(gone.map((item) => item.path));
    return result;
  }

  /// The Pod-relative path of every file inside [folder], however deep.

  static Future<List<String>> filesUnder(MediaItem folder) async {
    final found = <String>[];
    for (final child in await PodMediaService.listFolder(folder.path)) {
      if (child.isFolder) {
        found.addAll(await filesUnder(child));
      } else {
        found.add(child.path);
      }
    }
    return found;
  }

  /// The names [items] carry ON THE SERVER, split into files and folders.
  ///
  /// This has to be the stored name, `3f9c…e1.jpg.enc.ttl`, and never the
  /// name shown to the user, `beach.jpg`. Asking the server to delete a name
  /// that is not there answers 404, which the delete helper deliberately
  /// counts as success — so a display name makes delete report that it
  /// worked while quietly leaving the file in place.

  static ({List<String> files, List<String> folders}) storedNamesOf(
    List<MediaItem> items,
  ) => (
    files: [
      for (final item in items)
        if (!item.isFolder) item.rawName,
    ],
    folders: [
      for (final item in items)
        if (item.isFolder) item.rawName,
    ],
  );

  // Copy the file [item] into the store under a new random name, known to
  // the user as [name], returning the path of the copy.
  //
  // The name is recorded before the file is written: a name whose file never
  // arrives is never matched, while a file written without its name would
  // show up under the random one.

  static Future<String> _copyFile(MediaItem item, String name) async {
    final bytes = await PodMediaService.readBytes(item);
    final path = await MediaStore.newPath(name);
    await MediaCatalog.set(path, name, taken: item.taken, from: item.path);
    await PodMediaService.writeMedia(path: path, bytes: bytes, name: name);
    await MediaRenditions.copy(item.path, path);
    return path;
  }
}
