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
import 'package:photopod/services/media_names.dart';
import 'package:photopod/services/media_renditions.dart';
import 'package:photopod/services/pod_media_service.dart';
import 'package:photopod/utils/resource_name.dart';

/// The operations the toolbar performs on whole items rather than on bytes.
///
/// Solid has no server-side copy or rename. A file is stored under a random
/// name and known to the user by the name [MediaNames] keeps for it, so
/// renaming a file only changes that table. A copy is a read and a write, and
/// a folder, whose name is its name on the server, is renamed by copying
/// everything inside it and removing the original, which is why renaming a
/// folder can take a little while.

class PodMediaOps {
  const PodMediaOps._();

  /// Make a copy of each of [items] beside the original, returning the
  /// Pod-relative path of every copy keyed by the path it was copied from.
  ///
  /// The copy is named after the original with `_copy` before the extension,
  /// or `_copy_1`, `_copy_2` and so on when that is taken, so that nothing is
  /// ever confused with the original. Folders are left out: a duplicate is a
  /// photo or a video. Each folder is listed once, however many of its files
  /// are being duplicated, and the names handed out along the way are
  /// remembered so two copies made together cannot collide.

  static Future<Map<String, String>> duplicateAll(List<MediaItem> items) async {
    final copies = <String, String>{};
    final taken = <String, Set<String>>{};

    for (final item in items) {
      if (item.isFolder) continue;
      final parent = item.parentPath;
      final names = taken[parent] ??= await namesIn(parent);
      final name = duplicateName(item.name, names);
      copies[item.path] = await _copyFile(item, parent, name);
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

  /// Rename [item] to [newName] within its own folder, returning the
  /// Pod-relative path it now has.
  ///
  /// A file keeps its path, since only its entry in [MediaNames] changes. A
  /// folder is moved to a path of its new name.

  static Future<String> rename(MediaItem item, String newName) async {
    final parent = item.parentPath;

    if (!item.isFolder) {
      final names = await namesIn(parent)
        ..remove(item.name);
      if (names.contains(newName)) throw _clash(newName);
      await MediaNames.set(item.path, newName);
      return item.path;
    }

    final parentUrl = await PodMediaService.folderUrl(parent);
    final encoded = safeResourceName(newName);
    if (await PodMediaService.folderExists('$parentUrl$encoded/')) {
      throw _clash(newName);
    }

    final newPath = '$parent/$encoded';
    await _copyFolder(item, newPath);
    await MediaNames.copy({item.path: newPath});
    await _delete(item);
    return newPath;
  }

  /// Delete [items], which all sit in [parentPodPath]. Folders are removed
  /// with everything inside them, and so are the renditions and the names of
  /// everything that went.

  static Future<BatchDeleteResult> deleteAll(
    String parentPodPath,
    List<MediaItem> items,
  ) async {
    final names = storedNamesOf(items);
    final result = await deleteItems(
      parentPath: parentPodPath,
      fileNames: names.files,
      directoryNames: names.folders,
    );
    final gone = items
        .where((item) => !result.failed.containsKey(item.rawName))
        .toList();
    await MediaRenditions.forget(gone);
    await MediaNames.forget(gone.map((item) => item.path));
    return result;
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

  /// [wanted], or the first of `wanted (2)`, `wanted (3)` and so on, with the
  /// number before the extension, that is not among the names already
  /// [taken], so that a newly added file is never mistaken for one that is
  /// already in the folder.

  static String freeName(String wanted, Set<String> taken) {
    if (!taken.contains(wanted)) return wanted;

    final dot = wanted.lastIndexOf('.');
    final stem = dot <= 0 ? wanted : wanted.substring(0, dot);
    final suffix = dot <= 0 ? '' : wanted.substring(dot);

    for (var n = 2; ; n++) {
      final candidate = '$stem ($n)$suffix';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  /// The names the user sees for the files in [podPath].

  static Future<Set<String>> namesIn(String podPath) async => {
    for (final each in await PodMediaService.listFolder(podPath))
      if (!each.isFolder) each.name,
  };

  static PodMediaException _clash(String name) => PodMediaException(
    'Something called "$name" already exists in this folder.',
  );

  // Copy the file [item] into [destPodPath] under a new random name, known to
  // the user as [name], returning the path of the copy.
  //
  // The name is recorded before the file is written: a name whose file never
  // arrives is never matched, while a file written without its name would
  // show up under the random one.

  static Future<String> _copyFile(
    MediaItem item,
    String destPodPath,
    String name,
  ) async {
    final bytes = await PodMediaService.readBytes(item);
    final path = await PodMediaService.newStoredPath(destPodPath, name);
    await MediaNames.set(path, name);
    await PodMediaService.writeMedia(path: path, bytes: bytes);
    await MediaRenditions.copy(item.path, path);
    return path;
  }

  // Recreate the folder [item] at [destPath] with everything inside it,
  // walking one level at a time so that arbitrarily deep albums copy
  // correctly.
  //
  // Each file keeps the name it is stored under, so its name in [MediaNames]
  // follows it simply by the folder's path being rewritten. A plain file left
  // by an earlier build is encrypted on the way, as everything PhotoPod
  // writes is.

  static Future<void> _copyFolder(MediaItem item, String destPath) async {
    await PodMediaService.ensureFolder(
      await PodMediaService.folderUrl(destPath),
    );

    for (final child in await PodMediaService.listFolder(item.path)) {
      final stored = child.isEncrypted
          ? child.rawName
          : storedNameOf(child.rawName);
      final childPath = '$destPath/${child.isFolder ? child.rawName : stored}';

      if (child.isFolder) {
        await _copyFolder(child, childPath);
        continue;
      }
      await PodMediaService.writeMedia(
        path: childPath,
        bytes: await PodMediaService.readBytes(child),
      );
      await MediaRenditions.copy(child.path, childPath);

      // The path of a plain file changes by more than its folder, so a name
      // the user gave it is carried across by hand.

      final name = MediaNames.nameOf(child.path);
      if (stored != child.rawName && name != null) {
        await MediaNames.set(childPath, name);
      }
    }
  }

  // Remove a single item, recursing into folders.

  static Future<void> _delete(MediaItem item) async {
    final result = await deleteAll(item.parentPath, [item]);
    if (result.hasFailures) {
      throw PodMediaException(
        'Could not remove "${item.name}": ${result.failed.values.first}',
      );
    }
  }
}
