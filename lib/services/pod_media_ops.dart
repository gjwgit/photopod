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

import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/pod_media_service.dart';
import 'package:photopod/utils/resource_name.dart';

/// The operations the toolbar performs on whole items rather than on bytes.
///
/// Solid has no server-side copy or rename, so both are built from a read, a
/// write and — for a rename — a delete. Folders are handled by walking their
/// contents, which is why renaming a folder can take a little while.

class PodMediaOps {
  const PodMediaOps._();

  /// Make a copy of each of [items] beside the original, returning the
  /// Pod-relative path of every copy keyed by the path it was copied from.
  ///
  /// The copy is named after the original with `_copy` before the extension,
  /// or `_copy_1`, `_copy_2` and so on when that is taken, so that nothing is
  /// ever overwritten. Folders are left out: a duplicate is a photo or a
  /// video. Each folder is listed once, however many of its files are being
  /// duplicated, and the names handed out along the way are remembered so two
  /// copies made together cannot collide.

  static Future<Map<String, String>> duplicateAll(List<MediaItem> items) async {
    final copies = <String, String>{};
    final taken = <String, Set<String>>{};

    for (final item in items) {
      if (item.isFolder) continue;
      final parent = item.parentPath;
      final names = taken[parent] ??= {
        for (final each in await PodMediaService.listFolder(parent)) each.name,
      };
      final name = duplicateName(safeResourceName(item.name), names);
      await _copyAs(item, parent, name);
      names.add(name);
      copies[item.path] = newPathOf(item, parent, name);
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

  static Future<String> rename(MediaItem item, String newName) async {
    final parent = item.parentPath;
    final parentUrl = await PodMediaService.folderUrl(parent);

    final clashes = item.isFolder
        ? await PodMediaService.folderExists(
            '$parentUrl${safeResourceName(newName)}/',
          )
        : await PodMediaService.mediaExists(parent, newName);
    if (clashes) {
      throw PodMediaException(
        'Something called "$newName" already exists in this folder.',
      );
    }

    await _copyAs(item, parent, newName);
    await _delete(item);
    return newPathOf(item, parent, newName);
  }

  /// The Pod-relative path [item] takes when it is written into [destPodPath]
  /// under [name]. A file picks up the percent-encoding and the encryption
  /// suffix that [PodMediaService.writeMedia] gives it; a folder is simply
  /// its encoded name.

  static String newPathOf(MediaItem item, String destPodPath, String name) =>
      item.isFolder
      ? '$destPodPath/${safeResourceName(name)}'
      : PodMediaService.storedPath(destPodPath, name);

  /// Delete [items], which all sit in [parentPodPath]. Folders are removed
  /// with everything inside them.

  static Future<BatchDeleteResult> deleteAll(
    String parentPodPath,
    List<MediaItem> items,
  ) {
    final names = storedNamesOf(items);
    return deleteItems(
      parentPath: parentPodPath,
      fileNames: names.files,
      directoryNames: names.folders,
    );
  }

  /// The names [items] carry ON THE SERVER, split into files and folders.
  ///
  /// This has to be the stored name, `beach.jpg.enc.ttl`, and never the name
  /// shown to the user, `beach.jpg`. Asking the server to delete a name that
  /// is not there answers 404, which the delete helper deliberately counts as
  /// success — so a display name makes delete and rename report that they
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

  // Copy [item] into [destPodPath] under exactly [name].

  static Future<void> _copyAs(
    MediaItem item,
    String destPodPath,
    String name,
  ) async {
    final destUrl = await PodMediaService.folderUrl(destPodPath);
    final encoded = safeResourceName(name);

    if (!item.isFolder) {
      final bytes = await PodMediaService.readBytes(item);
      await PodMediaService.ensureFolder(destUrl);
      await PodMediaService.writeMedia(
        podPath: destPodPath,
        displayName: name,
        bytes: bytes,
      );
      return;
    }

    // A folder is recreated at the destination and then walked one level at
    // a time, so that arbitrarily deep albums copy correctly.

    final childPath = '$destPodPath/$encoded';
    await PodMediaService.ensureFolder('$destUrl$encoded/');
    final children = await PodMediaService.listFolder(item.path);
    for (final child in children) {
      await _copyAs(child, childPath, child.name);
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

  /// A name inside [destPodPath] that nothing is using yet.
  ///
  /// Derived from [wanted] by inserting " (2)", " (3)" and so on before the
  /// extension, so that a newly added file can never silently overwrite
  /// something already in the folder.

  static Future<String> freeName(
    String destPodPath,
    String wanted,
    bool isFolder,
  ) async {
    final destUrl = await PodMediaService.folderUrl(destPodPath);

    Future<bool> taken(String name) async {
      if (isFolder) {
        return PodMediaService.folderExists(
          '$destUrl${safeResourceName(name)}/',
        );
      }
      return PodMediaService.mediaExists(destPodPath, name);
    }

    if (!await taken(wanted)) return wanted;

    final dot = isFolder ? -1 : wanted.lastIndexOf('.');
    final stem = dot <= 0 ? wanted : wanted.substring(0, dot);
    final suffix = dot <= 0 ? '' : wanted.substring(dot);

    for (var n = 2; n < 100; n++) {
      final candidate = '$stem ($n)$suffix';
      if (!await taken(candidate)) return candidate;
    }
    throw PodMediaException(
      'Too many files called "$wanted" already exist at the destination.',
    );
  }
}
