/// The photos and videos the user has marked with a heart.
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
    show PathType, getDataDirPath, isUserLoggedIn, readPod, writePod;

import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/pod_media_service.dart';

/// The resource the list of favourites is kept in, inside the album folder.
///
/// The name deliberately does not end in `.ttl`: solidpod reads a Turtle
/// resource by parsing it, and this file holds JSON. It is also the reason
/// the file is written unencrypted — asking for the security key merely to
/// find out which photos carry a heart would put a password prompt in front
/// of an album that may hold nothing yet.

const String favouritesFileName = 'favourites.json';

/// Render [paths] as the JSON the Pod holds.
///
/// The list is sorted so that the same set of favourites always produces the
/// same bytes, which keeps a Pod's version history readable.

String encodeFavourites(Iterable<String> paths) {
  final sorted = paths.toList()..sort();
  return const JsonEncoder.withIndent(
    '  ',
  ).convert({'version': 1, 'favourites': sorted});
}

/// Read back what [encodeFavourites] wrote.
///
/// Anything that is not the expected shape yields an empty set rather than an
/// error: a corrupt or hand-edited file should cost the user their hearts, not
/// their access to the album.

Set<String> decodeFavourites(String text) {
  try {
    final decoded = jsonDecode(text);
    final list = decoded is Map<String, dynamic>
        ? decoded['favourites']
        : decoded;
    if (list is! List) return <String>{};
    return {
      for (final entry in list)
        if (entry is String && entry.isNotEmpty) entry,
    };
  } on FormatException {
    return <String>{};
  }
}

/// Which items carry a heart, held in the Pod so that the marks follow the
/// user from one device to the next.
///
/// Items are identified by their Pod-relative path, which is what survives
/// being read on another machine, where the absolute URL's host may differ.
/// A path that no longer resolves to anything is simply never matched, so a
/// file deleted outside PhotoPod leaves no visible trace.

class Favourites extends ChangeNotifier {
  final Set<String> _paths = <String>{};

  bool _loaded = false;
  String? _error;

  /// Writes are chained rather than issued in parallel, so that two quick
  /// taps on two hearts cannot race and leave the Pod holding the older of
  /// the two lists.

  Future<void> _writes = Future<void>.value();

  /// Whether the list has been read from the Pod yet.

  bool get isLoaded => _loaded;

  /// What went wrong the last time the Pod was read or written, if anything.

  String? get error => _error;

  /// How many items carry a heart.

  int get length => _paths.length;

  /// The Pod-relative paths of every favourite.

  Set<String> get paths => Set.unmodifiable(_paths);

  /// Whether [item] carries a heart.

  bool contains(MediaItem item) => _paths.contains(item.path);

  /// Whether every one of [items] carries a heart. An empty selection is not
  /// "all favourited", which is what makes the toolbar's heart offer to add
  /// rather than to remove.

  bool containsAll(Iterable<MediaItem> items) =>
      items.isNotEmpty && items.every(contains);

  /// Read the list from the Pod, leaving the set empty when the user has
  /// never favourited anything.

  Future<void> load() async {
    try {
      if (!await isUserLoggedIn()) return;
      final path = await _podPath();
      final url = await PodMediaService.folderUrl(await getDataDirPath());

      if (await PodMediaService.fileExists('$url$favouritesFileName')) {
        final content = await readPod(path, pathType: PathType.relativeToPod);
        _paths
          ..clear()
          ..addAll(decodeFavourites(content));
      }
      _error = null;
    } on Object catch (e) {
      _error = '$e';
      debugPrint('PhotoPod: could not read the favourites: $e');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// Add a heart to [items], or take it away from all of them.
  ///
  /// Every selected item ends up in the same state: if any one of them is not
  /// yet a favourite the whole selection becomes one, which is what a single
  /// heart button on a mixed selection should do. Returns false when the Pod
  /// refused the write, in which case the change is rolled back so that what
  /// is on screen still matches what is stored.

  Future<bool> toggleAll(Iterable<MediaItem> items) async {
    final files = items.where((item) => !item.isFolder).toList();
    if (files.isEmpty) return true;

    final before = Set<String>.from(_paths);
    final adding = !containsAll(files);

    for (final item in files) {
      if (adding) {
        _paths.add(item.path);
      } else {
        _paths.remove(item.path);
      }
    }
    notifyListeners();
    return _save(before);
  }

  /// Forget [paths] and anything filed beneath them, for items that have just
  /// been deleted. Folders are given as a path with no trailing slash, the
  /// same shape [MediaItem.path] uses.

  Future<bool> forget(Iterable<String> paths) async {
    final before = Set<String>.from(_paths);
    for (final path in paths) {
      _paths.removeWhere((each) => each == path || each.startsWith('$path/'));
    }
    if (_paths.length == before.length) return true;
    notifyListeners();
    return _save(before);
  }

  /// Follow items that have moved, so that a favourite stays a favourite
  /// after a move or a rename.
  ///
  /// [moves] maps the old Pod-relative path to the new one. A folder that has
  /// moved carries everything beneath it, so a path that merely starts with
  /// an old folder path is rewritten too.

  Future<bool> retarget(Map<String, String> moves) async {
    if (moves.isEmpty) return true;

    final before = Set<String>.from(_paths);
    final updated = <String>{};

    for (final path in _paths) {
      var moved = path;
      for (final entry in moves.entries) {
        if (path == entry.key) {
          moved = entry.value;
          break;
        }
        if (path.startsWith('${entry.key}/')) {
          moved = '${entry.value}${path.substring(entry.key.length)}';
          break;
        }
      }
      updated.add(moved);
    }

    if (setEquals(updated, _paths)) return true;
    _paths
      ..clear()
      ..addAll(updated);
    notifyListeners();
    return _save(before);
  }

  // Write the current set to the Pod, putting [before] back if the write is
  // refused so that the screen never claims more than the Pod holds.

  Future<bool> _save(Set<String> before) {
    final write = _writes.then((_) async {
      try {
        await writePod(
          await _podPath(),
          encodeFavourites(_paths),
          encrypted: false,
          overwrite: true,
          pathType: PathType.relativeToPod,
        );
        _error = null;
        return true;
      } on Object catch (e) {
        _error = '$e';
        _paths
          ..clear()
          ..addAll(before);
        notifyListeners();
        return false;
      }
    });

    // The chain itself must never carry the failure forward, or one refused
    // write would poison every write after it.

    _writes = write.then((_) {});
    return write;
  }

  static Future<String> _podPath() async =>
      '${await getDataDirPath()}/$favouritesFileName';
}
