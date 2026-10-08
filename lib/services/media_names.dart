/// The names the user gave each photo and video, kept apart from the random
/// names they are stored under.
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

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:photopod/constants/media.dart';
import 'package:photopod/services/encrypted_json_file.dart';
import 'package:photopod/services/pod_keys.dart';
import 'package:photopod/services/pod_media_service.dart';

/// The name of the table of names, at the top of the album. It is JSON,
/// stored encrypted as `names.json.enc.ttl`, since the names the user gives
/// their photos are as private as the photos; see [EncryptedJsonFile].

const String namesFileName = 'names.json';

const EncryptedJsonFile _file = EncryptedJsonFile(namesFileName);

/// How many random bytes go into a stored name: 128 bits, written as 32
/// hexadecimal digits.

const int _randomBytes = 16;

final Random _random = Random.secure();

/// A fresh random resource name for a file the user calls [displayName].
///
/// The name is a long run of hexadecimal digits followed by the file's
/// extension in lower case and the encryption suffix, so `海滩.JPG` might be
/// stored as `3f9c…e1.jpg.enc.ttl`. Every character is one a URL carries
/// unescaped, which is what solidpod's key bookkeeping needs, and the
/// extension keeps the kind of the file plain to anything that sees only the
/// stored name, such as someone the file is shared with.

String randomStoredName(String displayName) {
  final hex = [
    for (var i = 0; i < _randomBytes; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
  final extension = extensionOf(displayName);
  return '$hex${extension.isEmpty ? '' : '.$extension'}$encryptedSuffix';
}

/// Render [names] as the JSON the Pod holds, sorted so that the same names
/// always produce the same bytes.

String encodeNames(Map<String, String> names) {
  final sorted = Map.fromEntries(
    names.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
  return const JsonEncoder.withIndent(
    '  ',
  ).convert({'version': 1, 'names': sorted});
}

/// Read back what [encodeNames] wrote. Anything that is not the expected
/// shape yields no names rather than an error, so the files show under their
/// stored names instead of not at all.

Map<String, String> decodeNames(String text) {
  try {
    final decoded = jsonDecode(text);
    final names = decoded is Map<String, dynamic> ? decoded['names'] : null;
    if (names is! Map<String, dynamic>) return <String, String>{};
    return {
      for (final entry in names.entries)
        if (entry.value is String && (entry.value as String).isNotEmpty)
          entry.key: entry.value as String,
    };
  } on FormatException {
    return <String, String>{};
  }
}

/// The name the user knows each photo and video by, keyed by the Pod-relative
/// path of the file that holds it.
///
/// Every file PhotoPod adds is stored under a random name of its own, from
/// [randomStoredName], so a name in any script, with spaces or anything else
/// in it, never has to pass through a URL. The name the user chose lives
/// only here, and renaming a file changes nothing but this table.
///
/// A file with no entry is shown under its stored name, less the encryption
/// suffix, which is how the files added before random names keep the names
/// they had.

class MediaNames {
  const MediaNames._();

  static final Map<String, String> _names = <String, String>{};

  // The URL the table was read from, so that logging in as someone else reads
  // theirs, and the read in progress, so that the many listings a screen
  // starts at once share one request.

  static String? _loadedFrom;
  static Future<void>? _loading;

  // Writes are chained, as for the favourites, so two quick changes cannot
  // race and leave the Pod holding the older table.

  static Future<void> _writes = Future<void>.value();

  /// The name the user gave the file at Pod-relative [path], or null when it
  /// was never given one.

  static String? nameOf(String path) => _names[path];

  /// Whether the table is on the Pod but cannot be read until the user enters
  /// their security key, which is worth asking for before listing a folder.

  static Future<bool> needsKey() async =>
      !PodKeys.isPrimed &&
      _loadedFrom != await _file.url() &&
      await _file.exists();

  /// Read the table from the Pod, unless it has already been read for the
  /// user who is logged in.
  ///
  /// Without the security key the table is left unread, to be read by the
  /// next call once the key has been entered, and every file shows under its
  /// stored name meanwhile.

  static Future<void> ensureLoaded() async {
    final url = await _file.url();
    if (_loadedFrom == url) return;

    final loading = _loading ??= _load(url);
    try {
      await loading;
    } on SecurityKeyNeeded catch (e) {
      debugPrint('PhotoPod: file names not read yet: $e');
    } finally {
      if (identical(_loading, loading)) _loading = null;
    }
  }

  /// Read the table again next time it is needed, in case another device has
  /// changed it.

  static void invalidate() => _loadedFrom = null;

  /// Record that the file at [path] is called [name], and store the table.
  ///
  /// Throws [PodMediaException] when the Pod refuses the write, leaving the
  /// table as it was.

  static Future<void> set(String path, String name) =>
      _change((names) => names[path] = name);

  /// Copy the names of everything at or beneath each old path in [moves] to
  /// the matching new path, for files and folders that have been copied.

  static Future<void> copy(Map<String, String> moves) => _change((names) {
    for (final entry in _moved(names, moves).entries) {
      names[entry.key] = entry.value;
    }
  });

  /// Forget [paths], and everything beneath those that are folders, for items
  /// that have been deleted. Nothing that goes wrong is reported: a name left
  /// behind belongs to a path no file will ever have again.

  static Future<void> forget(Iterable<String> paths) async {
    final gone = paths.toList();
    if (gone.isEmpty) return;
    try {
      await _change(
        (names) => names.removeWhere(
          (path, _) => gone.any((each) => _within(path, each)),
        ),
      );
    } on Object catch (e) {
      debugPrint('PhotoPod: could not forget the names of deleted files: $e');
    }
  }

  // The entries of [names] at or beneath an old path of [moves], keyed by
  // where they now are.

  static Map<String, String> _moved(
    Map<String, String> names,
    Map<String, String> moves,
  ) => {
    for (final entry in names.entries)
      for (final move in moves.entries)
        if (_within(entry.key, move.key))
          '${move.value}${entry.key.substring(move.key.length)}': entry.value,
  };

  static bool _within(String path, String root) =>
      path == root || path.startsWith('$root/');

  // Apply [edit] to a copy of the table, store it, and only then adopt it.

  static Future<void> _change(void Function(Map<String, String>) edit) {
    final write = _writes.then((_) async {
      // A table that could not be read must not be written over with only
      // the change.

      await ensureLoaded();
      if (_loadedFrom != await _file.url()) {
        throw SecurityKeyNeeded(namesFileName);
      }

      final updated = Map<String, String>.from(_names);
      edit(updated);
      if (mapEquals(updated, _names)) return;

      try {
        await _file.write(encodeNames(updated));
      } on PodMediaException {
        rethrow;
      } on Object catch (e) {
        throw PodMediaException('The file names could not be saved: $e');
      }
      _names
        ..clear()
        ..addAll(updated);
    });

    // The chain itself never carries a failure forward, or one refused write
    // would fail every write after it.

    _writes = write.then((_) {}, onError: (_) {});
    return write;
  }

  static Future<void> _load(String url) async {
    final content = await _file.read();
    final names = content == null ? <String, String>{} : decodeNames(content);
    _names
      ..clear()
      ..addAll(names);
    _loadedFrom = url;
  }
}
