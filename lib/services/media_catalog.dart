/// One file holding everything PhotoPod knows about the user's photos and
/// videos, read once and kept in memory.
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/models/photo_metadata.dart';
import 'package:photopod/services/encrypted_json_file.dart';
import 'package:photopod/services/media_names.dart';
import 'package:photopod/services/pod_keys.dart';
import 'package:photopod/services/pod_media_service.dart';

/// The name of the catalog, at the top of the album. It is JSON, stored
/// encrypted as `catalog.json.enc.ttl`, since what it says about the photos
/// — names, places, who is in them — is as private as the photos.

const String catalogFileName = 'catalog.json';

const int catalogVersion = 2;

const EncryptedJsonFile _file = EncryptedJsonFile(catalogFileName);
const EncryptedJsonFile _legacy = EncryptedJsonFile(namesFileName);

/// The key the item at Pod-relative [path] is catalogued under: the random
/// part of its stored name, which stays the same wherever the item is moved,
/// or for an item from before random names, its path.

String catalogKeyOf(String path) {
  final stored = path.substring(path.lastIndexOf('/') + 1);
  return randomKeyOf(stored) ?? (isRandomFolderName(stored) ? stored : path);
}

/// Render [entries], keyed as [catalogKeyOf] keys them, as the JSON the Pod
/// holds, sorted so that the same catalog always produces the same bytes.

String encodeCatalog(Map<String, CatalogEntry> entries) {
  final keys = entries.keys.toList()..sort();
  return const JsonEncoder.withIndent('  ').convert({
    'version': catalogVersion,
    'items': {for (final key in keys) key: entries[key]!.toJson()},
  });
}

/// Read back what [encodeCatalog] wrote. Anything that is not the expected
/// shape yields an empty catalog rather than an error, so the files show
/// under their stored names instead of not at all.

Map<String, CatalogEntry> decodeCatalog(String text) {
  try {
    final decoded = jsonDecode(text);
    final items = decoded is Map<String, dynamic> ? decoded['items'] : null;
    if (items is! Map<String, dynamic>) return {};
    return {
      for (final item in items.entries)
        item.key: ?CatalogEntry.fromJson(item.value),
    };
  } on FormatException {
    return {};
  }
}

/// The catalog the table of names [text] amounts to: one entry for each path
/// it names or dates.

Map<String, CatalogEntry> catalogFromNames(String text) {
  final names = decodeNames(text);
  final dates = decodeDates(text);
  return {
    for (final path in {...names.keys, ...dates.keys})
      catalogKeyOf(path): CatalogEntry(
        path,
        name: names[path],
        taken: dates[path],
      ),
  };
}

/// Everything PhotoPod knows about each of the user's photos, videos and
/// folders, beyond what the Pod itself reports: the name the user gave it,
/// when it was taken, what its EXIF block says, and its tags and faces.
///
/// The catalog is read once, when it is first needed, and kept in memory, so
/// that a section can be drawn, and the map filled, without reading the
/// photos. Each item is keyed by [catalogKeyOf], and records its own path.
///
/// The catalog took over from the table of names, `names.json`. When there
/// is no catalog yet, that table is read and the catalog built from it; the
/// table is left as it was, for any older build still reading it.

class MediaCatalog {
  const MediaCatalog._();

  static final Map<String, CatalogEntry> _entries = {};

  // The URL the catalog was read from, so that logging in as someone else
  // reads theirs, and the read in progress, so that the many listings a
  // screen starts at once share one request.

  static String? _loadedFrom;
  static Future<void>? _loading;

  // Writes are chained, as for the favourites, so two quick changes cannot
  // race and leave the Pod holding the older catalog.

  static Future<void> _writes = Future<void>.value();

  /// The entry for the item at Pod-relative [path], if there is one.

  static CatalogEntry? entryOf(String path) {
    final entry = _entries[catalogKeyOf(path)];
    return entry?.path == path ? entry : null;
  }

  /// Every entry, in no particular order.

  static Iterable<CatalogEntry> get entries => _entries.values;

  /// The name the user gave the item at Pod-relative [path], or null.

  static String? nameOf(String path) => entryOf(path)?.name;

  /// When the photo or video at Pod-relative [path] was taken, or failing
  /// that when the file was last changed before it was added; null for a file
  /// whose date is not known yet.

  static DateTime? takenOf(String path) {
    final text = entryOf(path)?.taken;
    return text == null ? null : DateTime.tryParse(text);
  }

  /// What the photo at Pod-relative [path] says about itself, or null when
  /// its thumbnail has not been read yet.

  static PhotoMetadata? metadataOf(String path) => entryOf(path)?.metadata;

  /// Whether the catalog is on the Pod but cannot be read until the user
  /// enters their security key, which is worth asking for before listing a
  /// folder.

  static Future<bool> needsKey() async =>
      !PodKeys.isPrimed &&
      _loadedFrom != await _file.url() &&
      (await _file.exists() || await _legacy.exists());

  /// Read the catalog from the Pod, unless it has already been read for the
  /// user who is logged in.
  ///
  /// Without the security key the catalog is left unread, to be read by the
  /// next call once the key has been entered, and every file shows under its
  /// stored name meanwhile.

  static Future<void> ensureLoaded() async {
    final url = await _file.url();
    if (_loadedFrom == url) return;

    final loading = _loading ??= _load(url);
    try {
      await loading;
    } on SecurityKeyNeeded catch (e) {
      debugPrint('PhotoPod: the catalog was not read yet: $e');
    } finally {
      if (identical(_loading, loading)) _loading = null;
    }
  }

  /// Read the catalog again next time it is needed, in case another device
  /// has changed it.

  static void invalidate() => _loadedFrom = null;

  /// Record that the item at [path] is called [name], with the date it
  /// belongs under, [taken], and its EXIF details, [metadata], when given.
  /// Whatever is already known and not given is kept, so renaming a photo
  /// neither moves it to another day nor loses its tags. A new entry made
  /// for a copy starts from the entry of the item at [from].
  ///
  /// Throws [PodMediaException] when the Pod refuses the write, leaving the
  /// catalog as it was.

  static Future<void> set(
    String path,
    String name, {
    DateTime? taken,
    PhotoMetadata? metadata,
    String? from,
  }) => _change((entries) {
    final key = catalogKeyOf(path);
    final base =
        _at(entries, path) ??
        (from == null ? null : _at(entries, from)) ??
        CatalogEntry(path);
    entries[key] = base.copyWith(
      path: path,
      name: name,
      taken: taken == null ? null : encodeDate(taken),
      metadata: metadata,
    );
  });

  /// Record every name in [names], keyed by path, in a single write, for a
  /// whole folder of items that have just been given new paths. Each path
  /// [moves] names as the new place of an old one takes over everything else
  /// known about the old one.

  static Future<void> setAll(
    Map<String, String> names, {
    Map<String, String> moves = const {},
  }) async {
    if (names.isEmpty && moves.isEmpty) return;
    await _change((entries) {
      for (final move in moves.entries) {
        final old = _at(entries, move.key);
        if (old == null) continue;
        entries[catalogKeyOf(move.value)] = old.copyWith(path: move.value);
      }
      for (final named in names.entries) {
        final key = catalogKeyOf(named.key);
        entries[key] = (_at(entries, named.key) ?? CatalogEntry(named.key))
            .copyWith(name: named.value);
      }
    });
  }

  /// Record the date each path in [dates] belongs under, leaving alone any
  /// path that already has one, and store the catalog once for them all.

  static Future<void> setDates(Map<String, DateTime> dates) =>
      _change((entries) {
        for (final date in dates.entries) {
          final entry = _forUpdate(entries, date.key);
          if (entry == null || entry.taken != null) continue;
          entries[catalogKeyOf(date.key)] = entry.copyWith(
            taken: encodeDate(date.value),
          );
        }
      });

  /// Record what each photo in [details] says about itself, keyed by path,
  /// and store the catalog once for them all. A photo with no date yet takes
  /// the one in its details, or failing that its date in [dates].

  static Future<void> setMetadata(
    Map<String, PhotoMetadata> details, {
    Map<String, DateTime> dates = const {},
  }) => _change((entries) {
    for (final detail in details.entries) {
      final entry = _forUpdate(entries, detail.key);
      if (entry == null) continue;
      final when = detail.value.taken ?? dates[detail.key];
      entries[catalogKeyOf(detail.key)] = entry.copyWith(
        metadata: detail.value,
        taken: entry.taken ?? (when == null ? null : encodeDate(when)),
      );
    }
  });

  /// Give the item at [path] the title [title], merged with the one it
  /// has as [PhotoTitle.merge] says: the user's own words always win, and a
  /// service's suggestion fills in only where the user has given none.

  static Future<void> setTitle(String path, PhotoTitle title) =>
      _change((entries) {
        final entry = _forUpdate(entries, path);
        if (entry == null) return;
        entries[catalogKeyOf(path)] = entry.withTitle(
          PhotoTitle.merge(entry.title, title),
        );
      });

  /// The title of the item at Pod-relative [path], if it has one.

  static PhotoTitle? titleOf(String path) => entryOf(path)?.title;

  /// Replace the tags of the item at [path] with [tags].

  static Future<void> setTags(String path, List<PhotoTag> tags) => _change((
    entries,
  ) {
    final entry = _forUpdate(entries, path);
    if (entry != null) entries[catalogKeyOf(path)] = entry.copyWith(tags: tags);
  });

  /// Replace the faces in the photo at [path] with [faces].

  static Future<void> setFaces(String path, List<PhotoFace> faces) =>
      _change((entries) {
        final entry = _forUpdate(entries, path);
        if (entry != null) {
          entries[catalogKeyOf(path)] = entry.copyWith(faces: faces);
        }
      });

  /// Forget [paths], and everything beneath those that are folders, for items
  /// that have been deleted. Nothing that goes wrong is reported: an entry
  /// left behind belongs to a path no file will ever have again.

  static Future<void> forget(Iterable<String> paths) async {
    final gone = paths.toList();
    if (gone.isEmpty) return;
    try {
      await _change(
        (entries) => entries.removeWhere(
          (_, entry) => gone.any((each) => _within(entry.path, each)),
        ),
      );
    } on Object catch (e) {
      debugPrint('PhotoPod: could not forget the entries of deleted items: $e');
    }
  }

  // The entry for [path] in [entries], if it is still there.

  static CatalogEntry? _at(Map<String, CatalogEntry> entries, String path) {
    final entry = entries[catalogKeyOf(path)];
    return entry?.path == path ? entry : null;
  }

  // The entry to update for [path], a new one when there is none, or null
  // when [path] is out of date: its key belongs to an item that has moved
  // since, whose entry must not be overwritten with the old path.

  static CatalogEntry? _forUpdate(
    Map<String, CatalogEntry> entries,
    String path,
  ) {
    final entry = entries[catalogKeyOf(path)];
    if (entry == null) return CatalogEntry(path);
    return entry.path == path ? entry : null;
  }

  static bool _within(String path, String root) =>
      path == root || path.startsWith('$root/');

  // Apply [edit] to a copy of the catalog, store it, and only then adopt it.

  static Future<void> _change(
    void Function(Map<String, CatalogEntry> entries) edit,
  ) {
    final write = _writes.then((_) async {
      // A catalog that could not be read must not be written over with only
      // the change.

      await ensureLoaded();
      if (_loadedFrom != await _file.url()) {
        throw SecurityKeyNeeded(catalogFileName);
      }

      final updated = Map<String, CatalogEntry>.from(_entries);
      edit(updated);
      final text = encodeCatalog(updated);
      if (text == encodeCatalog(_entries)) return;

      await _store(text);
      _entries
        ..clear()
        ..addAll(updated);
    });

    // The chain itself never carries a failure forward, or one refused write
    // would fail every write after it.

    _writes = write.then((_) {}, onError: (_) {});
    return write;
  }

  static Future<void> _store(String text) async {
    try {
      await _file.write(text);
    } on PodMediaException {
      rethrow;
    } on Object catch (e) {
      throw PodMediaException('The catalog could not be saved: $e');
    }
  }

  static Future<void> _load(String url) async {
    final content = await _file.read();
    final Map<String, CatalogEntry> loaded;
    if (content != null) {
      loaded = decodeCatalog(content);
    } else {
      // No catalog yet: build it from the table of names, if there is one,
      // and store it, so the table is read only this once.

      final names = await _legacy.read();
      loaded = names == null ? {} : catalogFromNames(names);
      if (loaded.isNotEmpty) await _store(encodeCatalog(loaded));
    }
    _entries
      ..clear()
      ..addAll(loaded);
    _loadedFrom = url;
  }
}
