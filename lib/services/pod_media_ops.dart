/// Copy, move, rename and delete media in the Pod.
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

/// The operations the toolbar performs on whole items rather than on bytes.
///
/// Solid has no server-side copy or move, so both are built from a read, a
/// write and — for a move — a delete. Folders are handled by walking their
/// contents, which is why a folder copy can take a little while.

class PodMediaOps {
  const PodMediaOps._();

  /// Create a folder called [name] inside [parentPodPath].

  static Future<void> createFolder(String parentPodPath, String name) async {
    final parentUrl = await PodMediaService.folderUrl(parentPodPath);
    final url = '$parentUrl${Uri.encodeComponent(name)}/';
    if (await PodMediaService.folderExists(url)) {
      throw PodMediaException('A folder called "$name" already exists here.');
    }
    await PodMediaService.ensureFolder(url);
  }

  /// Create [podPath] and every folder along the way that is missing.
  ///
  /// [rootPath] is taken as already there and is never created; only the
  /// segments below it are. Servers differ on whether a write creates the
  /// containers above it, so each one is asked for explicitly.

  static Future<void> createFolderPath(String rootPath, String podPath) async {
    if (!podPath.startsWith(rootPath)) {
      throw PodMediaException(
        'The destination "$podPath" is outside "$rootPath".',
      );
    }

    var built = rootPath;
    final tail = podPath
        .substring(rootPath.length)
        .split('/')
        .where((segment) => segment.isNotEmpty);

    for (final segment in tail) {
      built = '$built/$segment';
      await PodMediaService.ensureFolder(
        await PodMediaService.folderUrl(built),
      );
    }
  }

  /// Copy [items] into the folder at [destPodPath].
  ///
  /// A name already in use at the destination is given a numeric suffix
  /// rather than being overwritten, so copying into the folder an item came
  /// from produces `beach (2).jpg` and nothing is ever lost.

  static Future<void> copyItems(
    List<MediaItem> items,
    String destPodPath,
  ) async {
    for (final item in items) {
      await _copyInto(item, destPodPath);
    }
  }

  /// Copy [item] into [destPodPath] under exactly [newName].
  ///
  /// Unlike [copyItems], a name the user has typed is never quietly given a
  /// numeric suffix: being handed `sunset.jpg` and silently producing
  /// `sunset (2).jpg` would be worse than saying the name is taken.

  static Future<void> copyAs(
    MediaItem item,
    String destPodPath,
    String newName,
  ) async {
    if (await PodMediaService.mediaExists(destPodPath, newName)) {
      throw PodMediaException(
        'Something called "$newName" is already in "$destPodPath".',
      );
    }
    await _copyAs(item, destPodPath, newName);
  }

  /// Move [item] into [destPodPath] under exactly [newName].
  ///
  /// Moving into the folder the item is already in is how a rename is
  /// expressed through the destination field, and works the same way: the
  /// item is written under its new name and the original removed.

  static Future<void> moveAs(
    MediaItem item,
    String destPodPath,
    String newName,
  ) async {
    await copyAs(item, destPodPath, newName);
    await _delete(item);
  }

  /// Move [items] into the folder at [destPodPath], by copying and then
  /// removing the originals. Anything that fails to copy is left in place.

  static Future<void> moveItems(
    List<MediaItem> items,
    String destPodPath,
  ) async {
    for (final item in items) {
      if (item.isFolder && _isInside(destPodPath, item.path)) {
        throw PodMediaException(
          'A folder cannot be moved into itself: "${item.name}".',
        );
      }
      await _copyInto(item, destPodPath);
      await _delete(item);
    }
  }

  /// Rename [item] to [newName] within its own folder.

  static Future<void> rename(MediaItem item, String newName) async {
    final parent = item.parentPath;
    final parentUrl = await PodMediaService.folderUrl(parent);

    final clashes = item.isFolder
        ? await PodMediaService.folderExists(
            '$parentUrl${Uri.encodeComponent(newName)}/',
          )
        : await PodMediaService.mediaExists(parent, newName);
    if (clashes) {
      throw PodMediaException(
        'Something called "$newName" already exists in this folder.',
      );
    }

    await _copyAs(item, parent, newName);
    await _delete(item);
  }

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

  // Copy [item] into [destPodPath], choosing a name that is free there.

  static Future<void> _copyInto(MediaItem item, String destPodPath) async {
    final name = await freeName(destPodPath, item.name, item.isFolder);
    await _copyAs(item, destPodPath, name);
  }

  // Copy [item] into [destPodPath] under exactly [name].

  static Future<void> _copyAs(
    MediaItem item,
    String destPodPath,
    String name,
  ) async {
    final destUrl = await PodMediaService.folderUrl(destPodPath);
    final encoded = Uri.encodeComponent(name);

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
  /// extension, so that neither a copy nor a newly added file can ever
  /// silently overwrite something already in the folder.

  static Future<String> freeName(
    String destPodPath,
    String wanted,
    bool isFolder,
  ) async {
    final destUrl = await PodMediaService.folderUrl(destPodPath);

    Future<bool> taken(String name) async {
      if (isFolder) {
        return PodMediaService.folderExists(
          '$destUrl${Uri.encodeComponent(name)}/',
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

  // Whether [inner] sits at or below [outer], used to refuse a move that
  // would place a folder inside itself.

  static bool _isInside(String inner, String outer) {
    final base = outer.endsWith('/') ? outer : '$outer/';
    final target = inner.endsWith('/') ? inner : '$inner/';
    return target == base || target.startsWith(base);
  }
}
