/// Move photos, videos and folders to random names on the Pod.
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

import 'package:solidpod/solidpod.dart' show deleteItems, getFileUrl;

import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/album_sharing.dart';
import 'package:photopod/services/media_names.dart';
import 'package:photopod/services/media_renditions.dart';
import 'package:photopod/services/pod_media_ops.dart';
import 'package:photopod/services/pod_media_service.dart';

/// Moving items from the names they were stored under to random ones.
///
/// Anything added before random names is stored under the name it arrived
/// with, `PXL_20240726_211937668.jpg.enc.ttl`, or the name a folder was given,
/// and so tells anyone who can see the server what it is. Solid has no
/// rename, so each such item is written again under a random name and the
/// original removed, carrying along everything that hangs off it: its name,
/// its renditions, and everyone it is shared with. A move changes the item's
/// path, so the caller retargets the hearts, the albums and the record of
/// album sharing with the map of moves these return.

class PodMediaMoves {
  const PodMediaMoves._();

  /// Move the file [item] to a random name in its own folder, known to the
  /// user as [name], or as before when that is not given. Returns the new
  /// Pod-relative path, or throws [PodMediaException], having left the
  /// original in place, when the copy cannot be made.
  ///
  /// [failures] collects the access that could not be carried across, which
  /// leaves the file moved but not shared with someone it was shared with.

  static Future<String> moveFile(
    MediaItem item, {
    String? name,
    List<String>? failures,
  }) async {
    final display = name ?? item.name;
    final media = await PodMediaService.readMedia(item);
    final path = await PodMediaService.newStoredPath(item.parentPath, display);
    await MediaNames.set(path, display, taken: item.taken);
    await PodMediaService.writeMedia(
      path: path,
      bytes: media.bytes,
      name: display,
    );
    await MediaRenditions.copy(item.path, path);
    final carried = await carryAccess(item.url, await getFileUrl(path));
    failures?.addAll(carried.map((each) => '${item.name}: $each'));

    final result = await PodMediaOps.deleteAll(item.parentPath, [item]);
    if (result.hasFailures) {
      throw PodMediaException(
        'A copy of "${item.name}" was made, but the original could not be '
        'removed: ${result.failed.values.first}',
      );
    }
    return path;
  }

  /// Move the folder [item], and everything in it, to a random name in its
  /// own parent, known to the user as [name], or as before when that is not
  /// given. Returns every move made, keyed by the old Pod-relative path, the
  /// folder's own included.
  ///
  /// The files inside that already have random names keep them, and so keep
  /// their renditions as they are; the others are moved to random names as
  /// [moveFile] would. Folders inside are given random names too.

  static Future<Map<String, String>> moveFolder(
    MediaItem item, {
    String? name,
    List<String>? failures,
  }) async {
    final dest = '${item.parentPath}/${randomFolderName()}';
    final moves = <String, String>{item.path: dest};
    final names = <String, String>{dest: name ?? item.name};
    final renamedFiles = <String>[];

    await _copyInto(item, dest, moves, names, renamedFiles, failures ?? []);

    // The names go in before the original goes, so that nothing is ever on
    // the Pod without one, and each file takes its date along.

    await MediaNames.setAll(names, moves: moves);

    final result = await deleteItems(
      parentPath: item.parentPath,
      fileNames: const [],
      directoryNames: [item.rawName],
    );
    if (result.hasFailures) {
      throw PodMediaException(
        'A copy of "${item.name}" was made, but the original could not be '
        'removed: ${result.failed.values.first}',
      );
    }

    // Only the renditions of the files that changed name belong to the old
    // paths; the others are filed under names that did not change.

    await MediaRenditions.forget([item], inside: renamedFiles);
    await MediaNames.forget([item.path]);
    return moves;
  }

  // Copy everything in [folder] into [dest], recording each move in [moves],
  // each name in [names], and in [renamedFiles] the old path of every file
  // that was given a new name.

  static Future<void> _copyInto(
    MediaItem folder,
    String dest,
    Map<String, String> moves,
    Map<String, String> names,
    List<String> renamedFiles,
    List<String> failures,
  ) async {
    await PodMediaService.ensureFolder(await PodMediaService.folderUrl(dest));

    for (final child in await PodMediaService.listFolder(folder.path)) {
      if (child.isFolder) {
        final childDest =
            '$dest/${isRandomFolderName(child.rawName) ? child.rawName : randomFolderName()}';
        moves[child.path] = childDest;
        names[childDest] = child.name;
        await _copyInto(child, childDest, moves, names, renamedFiles, failures);
        continue;
      }

      final keep = isRandomStoredName(child.rawName);
      final childDest = keep
          ? '$dest/${child.rawName}'
          : await PodMediaService.newStoredPath(dest, child.name);
      await PodMediaService.writeMedia(
        path: childDest,
        bytes: await PodMediaService.readBytes(child),
        name: child.name,
      );
      if (!keep) {
        renamedFiles.add(child.path);
        await MediaRenditions.copy(child.path, childDest);
      }
      final carried = await carryAccess(child.url, await getFileUrl(childDest));
      failures.addAll(carried.map((each) => '${child.name}: $each'));
      moves[child.path] = childDest;
      names[childDest] = child.name;
    }
  }
}
