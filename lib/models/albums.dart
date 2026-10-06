/// The albums the user has gathered photos and videos into.
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
        ResourceContentType,
        deleteResource,
        getDataDirPath,
        isUserLoggedIn,
        readPod,
        writePod;

import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/pod_media_service.dart';
import 'package:photopod/utils/name_validator.dart';

/// The folder, inside the album root, that holds one JSON file per album.
///
/// The Library hides it, so it never appears among the user's own folders,
/// and it holds nothing but the album files: as many files, as many albums.

const String albumsFolderName = 'albums';

/// The extension every album file carries. The file name without it is the
/// album's name.

const String albumFileExtension = '.json';

/// The name Favourites goes by when it is shown among the albums. It is a
/// system album, so no album of the user's own may take the same name.

const String favouritesAlbumName = 'Favourites';

/// Render [paths] as the JSON an album file holds.
///
/// The same shape as the list of favourites, and for the same reason sorted,
/// so that the same album always produces the same bytes.

String encodeAlbum(Iterable<String> paths) {
  final sorted = paths.toList()..sort();
  return const JsonEncoder.withIndent(
    '  ',
  ).convert({'version': 1, 'items': sorted});
}

/// Read back what [encodeAlbum] wrote.
///
/// A damaged file yields an empty album rather than an error, so one bad file
/// cannot keep the user away from every other album.

Set<String> decodeAlbum(String text) {
  try {
    final decoded = jsonDecode(text);
    final list = decoded is Map<String, dynamic> ? decoded['items'] : decoded;
    if (list is! List) return <String>{};
    return {
      for (final entry in list)
        if (entry is String && entry.isNotEmpty) entry,
    };
  } on FormatException {
    return <String>{};
  }
}

/// Check [name] as the name of a new album, returning why it cannot be used,
/// or null when it is fine.
///
/// The name becomes the name of the album's file, so it follows the same
/// rules as a folder name. It must also differ, ignoring case, from every
/// album already there — [existing] — and from Favourites. [current] is the
/// album being renamed, which may keep its own name in a different case.

String? validateAlbumName(
  String name, {
  Iterable<String> existing = const [],
  String? current,
}) {
  final problem = validateName(name, isFolder: true);
  if (problem != null) return problem;

  final lower = name.toLowerCase();
  if (lower == favouritesAlbumName.toLowerCase()) {
    return 'Favourites is the album your hearts go into, so no other album '
        'can be called that.';
  }
  for (final other in existing) {
    if (other == current) continue;
    if (other.toLowerCase() == lower) {
      return 'There is already an album called "$other".';
    }
  }
  return null;
}

/// Every album the user has made, each a set of Pod-relative paths, held in
/// the Pod so that the albums follow the user from one device to the next.
///
/// Each album is a file of its own in [albumsFolderName], named after the
/// album. Items are identified exactly as favourites are, by their
/// Pod-relative path, and a path that no longer resolves to anything is simply
/// never matched.

class Albums extends ChangeNotifier {
  final Map<String, Set<String>> _albums = <String, Set<String>>{};

  bool _loaded = false;
  String? _error;

  /// Writes are chained rather than issued in parallel, so that two changes
  /// in quick succession cannot race and leave the older one on the Pod.

  Future<void> _writes = Future<void>.value();

  /// Whether the albums have been read from the Pod yet.

  bool get isLoaded => _loaded;

  /// What went wrong the last time the Pod was read or written, if anything.

  String? get error => _error;

  /// The names of every album, in alphabetical order, ignoring case.

  List<String> get names =>
      _albums.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// Whether an album called [name] exists.

  bool exists(String name) => _albums.containsKey(name);

  /// The Pod-relative paths of everything in the album called [name].

  Set<String> pathsOf(String name) =>
      Set.unmodifiable(_albums[name] ?? const <String>{});

  /// Whether the album called [name] holds [item].

  bool contains(String name, MediaItem item) =>
      _albums[name]?.contains(item.path) ?? false;

  /// Read every album from the Pod.

  Future<void> load() async {
    try {
      if (!await isUserLoggedIn()) return;
      final folder = await _folderPath();
      await PodMediaService.ensureFolder(
        await PodMediaService.folderUrl(folder),
      );

      final found = <String, Set<String>>{};
      for (final entry in await PodMediaService.listFolder(folder)) {
        if (entry.isFolder || !entry.rawName.endsWith(albumFileExtension)) {
          continue;
        }
        final name = entry.name.substring(
          0,
          entry.name.length - albumFileExtension.length,
        );
        // Favourites has a file of its own elsewhere, so a stray album file
        // of the same name, made outside PhotoPod, is passed over rather
        // than shown as a second Favourites.

        if (name.isEmpty ||
            name.toLowerCase() == favouritesAlbumName.toLowerCase()) {
          continue;
        }
        final content = await readPod(
          entry.path,
          pathType: PathType.relativeToPod,
        );
        found[name] = decodeAlbum(content);
      }

      _albums
        ..clear()
        ..addAll(found);
      _error = null;
    } on Object catch (e) {
      _error = '$e';
      debugPrint('PhotoPod: could not read the albums: $e');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// Make a new, empty album called [name]. Returns false when the Pod
  /// refused, in which case no album appears.

  Future<bool> create(String name) async {
    if (_albums.containsKey(name)) return true;
    _albums[name] = <String>{};
    notifyListeners();

    final ok = await _chain(() => _write(name, const <String>{}));
    if (!ok) {
      _albums.remove(name);
      notifyListeners();
    }
    return ok;
  }

  /// Give the album called [from] the name [to].
  ///
  /// The album is written under its new name before the old file is removed,
  /// so a failure part way leaves the album where it was.

  Future<bool> rename(String from, String to) async {
    final paths = _albums[from];
    if (paths == null || from == to) return true;

    final ok = await _chain(() async {
      await _write(to, paths);
      await _remove(from);
    });
    if (ok) {
      _albums
        ..remove(from)
        ..[to] = paths;
      notifyListeners();
    }
    return ok;
  }

  /// Remove the album called [name]. The photos and videos in it stay where
  /// they are; only the album goes.

  Future<bool> delete(String name) async {
    final paths = _albums[name];
    if (paths == null) return true;

    final ok = await _chain(() => _remove(name));
    if (ok) {
      _albums.remove(name);
      notifyListeners();
    }
    return ok;
  }

  /// Put [items] into the album called [name]. Folders are left out, and an
  /// item already there is not added twice.

  Future<bool> add(String name, Iterable<MediaItem> items) async {
    final paths = _albums[name];
    if (paths == null) return false;

    final before = Set<String>.from(paths);
    paths.addAll([
      for (final item in items)
        if (!item.isFolder) item.path,
    ]);
    if (paths.length == before.length) return true;
    notifyListeners();
    return _save({name: before});
  }

  /// Take [items] out of the album called [name]. The files themselves stay
  /// in the Pod.

  Future<bool> remove(String name, Iterable<MediaItem> items) async {
    final paths = _albums[name];
    if (paths == null) return true;

    final before = Set<String>.from(paths);
    paths.removeAll(items.map((item) => item.path));
    if (paths.length == before.length) return true;
    notifyListeners();
    return _save({name: before});
  }

  /// Forget [paths] and anything filed beneath them in every album, for
  /// items that have just been deleted from the Pod.

  Future<bool> forget(Iterable<String> paths) async {
    final gone = paths.toList();
    final before = <String, Set<String>>{};

    for (final entry in _albums.entries) {
      final copy = Set<String>.from(entry.value);
      for (final path in gone) {
        entry.value.removeWhere(
          (each) => each == path || each.startsWith('$path/'),
        );
      }
      if (entry.value.length != copy.length) before[entry.key] = copy;
    }

    if (before.isEmpty) return true;
    notifyListeners();
    return _save(before);
  }

  /// Follow items that have been renamed, so that they stay in every album
  /// they were in. [moves] maps the old Pod-relative path to the new one.

  Future<bool> retarget(Map<String, String> moves) async {
    if (moves.isEmpty) return true;
    final before = <String, Set<String>>{};

    for (final entry in _albums.entries) {
      final updated = <String>{};
      for (final path in entry.value) {
        var moved = path;
        for (final move in moves.entries) {
          if (path == move.key) {
            moved = move.value;
            break;
          }
          if (path.startsWith('${move.key}/')) {
            moved = '${move.value}${path.substring(move.key.length)}';
            break;
          }
        }
        updated.add(moved);
      }
      if (!setEquals(updated, entry.value)) {
        before[entry.key] = Set<String>.from(entry.value);
        entry.value
          ..clear()
          ..addAll(updated);
      }
    }

    if (before.isEmpty) return true;
    notifyListeners();
    return _save(before);
  }

  // Write every album named in [before] to the Pod, putting all of them back
  // as they were if any write is refused, so that the screen never claims
  // more than the Pod holds.

  Future<bool> _save(Map<String, Set<String>> before) async {
    final ok = await _chain(() async {
      for (final name in before.keys) {
        final paths = _albums[name];
        if (paths != null) await _write(name, paths);
      }
    });
    if (!ok) {
      for (final entry in before.entries) {
        _albums[entry.key] = entry.value;
      }
      notifyListeners();
    }
    return ok;
  }

  // Run [action] after every write already queued, recording what went
  // wrong. The chain itself never carries a failure forward, or one refused
  // write would poison every write after it.

  Future<bool> _chain(Future<void> Function() action) {
    final write = _writes.then((_) async {
      try {
        await action();
        _error = null;
        return true;
      } on Object catch (e) {
        _error = '$e';
        return false;
      }
    });
    _writes = write.then((_) {});
    return write;
  }

  // The album files hold JSON, not Turtle, and are written unencrypted for
  // the same reason as the favourites: asking for the security key merely to
  // list the albums would put a password prompt in front of an empty page.

  static Future<void> _write(String name, Set<String> paths) async {
    final folder = await _folderPath();
    await PodMediaService.ensureFolder(await PodMediaService.folderUrl(folder));
    await writePod(
      '$folder/$name$albumFileExtension',
      encodeAlbum(paths),
      encrypted: false,
      overwrite: true,
      pathType: PathType.relativeToPod,
    );
  }

  // An album file is plain JSON with no encryption key and no sharing, so it
  // is removed with a bare DELETE rather than solidpod's file delete, which
  // would go on to look for a key and an access list that were never made.

  static Future<void> _remove(String name) async {
    final folderUrl = await PodMediaService.folderUrl(await _folderPath());
    final url =
        '${folderUrl.endsWith('/') ? folderUrl : '$folderUrl/'}'
        '$name$albumFileExtension';
    try {
      await deleteResource(url, ResourceContentType.any);
    } on Object catch (e) {
      // Already gone is as good as removed.

      if ('$e'.contains('404') || '$e'.contains('NotFound')) return;
      rethrow;
    }
  }

  static Future<String> _folderPath() async =>
      '${await getDataDirPath()}/$albumsFolderName';
}
