/// The one place every photo and video is stored.
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

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/media_names.dart';
import 'package:photopod/services/pod_media_service.dart';

/// The folder, at the top of the album, that holds every photo and video.

const String storeFolderName = 'media';

/// The folders inside the store, one for each hexadecimal digit a random
/// name can start with, so that no one folder grows so large the server is
/// slow to list it.

const List<String> storeShards = [
  '0', '1', '2', '3', '4', '5', '6', '7', //
  '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
];

/// The Pod-relative path, within the album at [root], at which the file
/// stored as [storedName] belongs: `media/3/3f9c…e1.jpg.enc.ttl`.

String storePathOf(String root, String storedName) =>
    '$root/$storeFolderName/${storedName[0]}/$storedName';

/// Every photo and video sits in the store, under its random name, and
/// nowhere else. Nothing is ever moved within it, so the path a photo is
/// given when it is added is the one it keeps: albums, favourites, sharing
/// and the catalog can all rely on it.
///
/// How the user organises their photos is up to the albums, in which a
/// photo can appear any number of times.

class MediaStore {
  const MediaStore._();

  // The shards known to exist this session, so each is asked after once.

  static final Set<String> _made = <String>{};

  /// A Pod-relative path in the store, under a fresh random name, for a new
  /// file the user calls [displayName]. The folder it goes into is made if
  /// it is not there yet.

  static Future<String> newPath(String displayName) async {
    final root = await PodMediaService.rootPath();
    final path = storePathOf(root, randomStoredName(displayName));
    await ensureShardOf(path);
    return path;
  }

  /// Make sure the folder the store path [path] goes into exists.

  static Future<void> ensureShardOf(String path) async {
    final shard = path.substring(0, path.lastIndexOf('/'));
    if (_made.contains(shard)) return;
    final store = shard.substring(0, shard.lastIndexOf('/'));
    await PodMediaService.ensureFolder(await PodMediaService.folderUrl(store));
    await PodMediaService.ensureFolder(await PodMediaService.folderUrl(shard));
    _made.add(shard);
  }

  /// Every photo and video in the store, one listing for each shard, all
  /// asked for at once. A shard nothing has gone into yet is empty.

  static Future<List<MediaItem>> list() async {
    final root = await PodMediaService.rootPath();
    final listings = await Future.wait([
      for (final shard in storeShards)
        _listShard('$root/$storeFolderName/$shard'),
    ]);
    return [
      for (final listing in listings)
        for (final item in listing)
          if (!item.isFolder) item,
    ];
  }

  static Future<List<MediaItem>> _listShard(String path) async {
    try {
      return await PodMediaService.listFolder(
        path,
        kinds: const {MediaKind.photo, MediaKind.video},
      );
    } on PodMediaException {
      if (!await PodMediaService.folderExists(
        await PodMediaService.folderUrl(path),
      )) {
        return const [];
      }
      rethrow;
    }
  }
}
