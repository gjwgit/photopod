/// Every photo and video in the album, wherever it is filed.
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

import 'package:flutter/foundation.dart';

import 'package:solidpod/solidpod.dart' show isUserLoggedIn;

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/pod_media_service.dart';

/// How many containers one scan will ask the server for.
///
/// Each folder is a separate round trip, so a deeply nested album could keep
/// the app waiting for a long time. The limit is generous enough for any
/// album a person has organised by hand, and the sections say plainly when
/// they have run into it.

const int maxScannedFolders = 400;

/// How deep the scan follows subfolders below the album root.

const int maxScanDepth = 12;

/// The whole album as one flat list, built by walking the folders.
///
/// The Favourites, Videos and Maps sections are views over the album rather
/// than over a folder, so none of them can be answered by a single container
/// listing. They share this index instead, which is scanned once and then
/// reused, and which the Library section invalidates whenever it changes
/// something on the Pod.

class MediaIndex extends ChangeNotifier {
  List<MediaItem> _items = const [];
  bool _loading = false;
  bool _stale = true;
  bool _truncated = false;
  String? _error;
  DateTime? _scannedAt;

  /// Every photo and video found, in the order the folders were walked.

  List<MediaItem> get items => _items;

  /// Whether a scan is running now.

  bool get isLoading => _loading;

  /// Whether the album has not been scanned yet, or has changed since.

  bool get isStale => _stale;

  /// Whether the scan gave up before it had seen every folder.

  bool get isTruncated => _truncated;

  /// What went wrong during the last scan, if anything.

  String? get error => _error;

  /// When the album was last walked.

  DateTime? get scannedAt => _scannedAt;

  /// Every video in the album.

  List<MediaItem> get videos =>
      _items.where((item) => item.isVideo).toList(growable: false);

  /// Every photo in the album.

  List<MediaItem> get photos =>
      _items.where((item) => item.isPhoto).toList(growable: false);

  /// Note that the album on the Pod has changed, so that the next section to
  /// ask for it walks the folders again.

  void invalidate() {
    _stale = true;
  }

  /// Walk the album, unless a scan is already running or the last one is
  /// still good and [force] was not asked for.

  Future<void> refresh({bool force = false}) async {
    if (_loading) return;
    if (!force && !_stale && _error == null) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      if (!await isUserLoggedIn()) {
        throw const PodMediaException(
          'Please log in to your Pod to see your album.',
        );
      }

      final root = await PodMediaService.rootPath();
      final found = <MediaItem>[];
      var scanned = 0;
      var truncated = false;

      // Breadth first, so that a limit reached in a very deep album still
      // leaves the user with everything near the top of it.

      final queue = <({String path, int depth})>[(path: root, depth: 0)];

      while (queue.isNotEmpty) {
        if (scanned >= maxScannedFolders) {
          truncated = true;
          break;
        }

        final folder = queue.removeAt(0);
        scanned++;

        final entries = await PodMediaService.listFolder(
          folder.path,
          kinds: const {MediaKind.photo, MediaKind.video},
        );

        for (final entry in entries) {
          if (!entry.isFolder) {
            found.add(entry);
          } else if (folder.depth < maxScanDepth) {
            queue.add((path: entry.path, depth: folder.depth + 1));
          } else {
            truncated = true;
          }
        }
      }

      _items = List.unmodifiable(found);
      _truncated = truncated;
      _stale = false;
      _scannedAt = DateTime.now();
    } on Object catch (e) {
      _error = '$e';
      _stale = true;
      debugPrint('PhotoPod: could not scan the album: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
