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
  final extension = extensionOf(displayName);
  return '${_randomHex()}${extension.isEmpty ? '' : '.$extension'}'
      '$encryptedSuffix';
}

/// A fresh random name for a folder, which is nothing but the hexadecimal
/// digits: a folder has no extension to keep, and the name the user gave it
/// lives in [MediaNames] like a file's.

String randomFolderName() => _randomHex();

String _randomHex() => [
  for (var i = 0; i < _randomBytes; i++)
    _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();

// The shape of every name [randomStoredName] hands out.

final RegExp _randomStoredName = RegExp(
  r'^[0-9a-f]{32}(\.[a-z0-9]+)?\.enc\.ttl$',
);

/// Whether [storedName] is one [randomStoredName] handed out, rather than a
/// name from before random names, which was the name the file arrived with
/// and so tells the server what the photo is.

bool isRandomStoredName(String storedName) =>
    _randomStoredName.hasMatch(storedName);

/// The random part of a name [randomStoredName] handed out, or null for any
/// other name. It is what the renditions of the file are filed under.

String? randomKeyOf(String storedName) =>
    isRandomStoredName(storedName) ? storedName.substring(0, 32) : null;

final RegExp _randomFolderName = RegExp(r'^[0-9a-f]{32}$');

/// Whether [folderName] is one [randomFolderName] handed out, rather than
/// the name the user typed, which the server would see.

bool isRandomFolderName(String folderName) =>
    _randomFolderName.hasMatch(folderName);

/// Render [names], and the [dates] the photos and videos were taken, as the
/// JSON the Pod holds, sorted so that the same table always produces the
/// same bytes.

String encodeNames(
  Map<String, String> names, [
  Map<String, String> dates = const {},
]) {
  Map<String, String> sorted(Map<String, String> map) => Map.fromEntries(
    map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
  return const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'names': sorted(names),
    if (dates.isNotEmpty) 'dates': sorted(dates),
  });
}

/// Read back what [encodeNames] wrote. Anything that is not the expected
/// shape yields no names rather than an error, so the files show under their
/// stored names instead of not at all.

Map<String, String> decodeNames(String text) => _decodeTable(text, 'names');

/// Read back the dates [encodeNames] wrote, as ISO 8601 text keyed by path.
/// A table written before dates were kept has none.

Map<String, String> decodeDates(String text) =>
    _decodeTable(text, 'dates')
      ..removeWhere((_, value) => DateTime.tryParse(value) == null);

Map<String, String> _decodeTable(String text, String key) {
  try {
    final decoded = jsonDecode(text);
    final table = decoded is Map<String, dynamic> ? decoded[key] : null;
    if (table is! Map<String, dynamic>) return <String, String>{};
    return {
      for (final entry in table.entries)
        if (entry.value is String && (entry.value as String).isNotEmpty)
          entry.key: entry.value as String,
    };
  } on FormatException {
    return <String, String>{};
  }
}

/// [when] as the table stores it.
///
/// A time with no zone, which is what an EXIF date is, is kept as the clock
/// on the camera read, so that a photo taken at ten past nine in the morning
/// stays on that day wherever it is later looked at. A file's own time is a
/// real instant, and is kept in UTC.

String encodeDate(DateTime when) => when.toIso8601String();

/// The name the user knows each photo, video and folder by, keyed by its
/// Pod-relative path.
///
/// Every file and folder PhotoPod makes is stored under a random name of its
/// own, from [randomStoredName] and [randomFolderName], so a name in any
/// script, with spaces or anything else in it, never has to pass through a
/// URL and never reaches the server. A file also carries its name inside
/// itself, encrypted, which is what someone it is shared with sees; this
/// table is what lets a folder be listed without reading every file in it.
///
/// An item with no entry is shown under its stored name, less the encryption
/// suffix, which is how anything added before random names keeps the name
/// it had until [StorageUpgrade] moves it.
///
/// The table also keeps the date each photo and video belongs under: when it
/// was taken, from its EXIF block, or failing that when the file itself was
/// last changed before it was added. The Pod only knows when the file was
/// uploaded, and keeping the date here, beside the name, means the Library
/// learns it from the one read it makes anyway.

class MediaNames {
  const MediaNames._();

  static final Map<String, String> _names = <String, String>{};
  static final Map<String, String> _dates = <String, String>{};

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

  /// When the photo or video at Pod-relative [path] was taken, or failing
  /// that when the file was last changed before it was added; null for a file
  /// added before dates were kept.

  static DateTime? takenOf(String path) {
    final text = _dates[path];
    return text == null ? null : DateTime.tryParse(text);
  }

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

  /// Record that the file at [path] is called [name], and, when [taken] is
  /// given, the date it belongs under, then store the table. A date already
  /// recorded is kept when [taken] is left out, so renaming a photo does not
  /// move it to another day.
  ///
  /// Throws [PodMediaException] when the Pod refuses the write, leaving the
  /// table as it was.

  static Future<void> set(String path, String name, {DateTime? taken}) =>
      _change((names, dates) {
        names[path] = name;
        if (taken != null) dates[path] = encodeDate(taken);
      });

  /// Record every name in [names], keyed by path, in a single write, for a
  /// whole folder of files that have just been given new paths. Each path
  /// [moves] names as the new place of an old one takes over the old one's
  /// date, so that a moved photo stays on its day.

  static Future<void> setAll(
    Map<String, String> names, {
    Map<String, String> moves = const {},
  }) async {
    if (names.isEmpty && moves.isEmpty) return;
    await _change((table, dates) {
      table.addAll(names);
      for (final move in moves.entries) {
        final date = dates[move.key];
        if (date != null) dates[move.value] = date;
      }
    });
  }

  /// Record the date each path in [dates] belongs under, leaving alone any
  /// path that already has one, and store the table once for them all.

  static Future<void> setDates(Map<String, DateTime> dates) =>
      _change((names, stored) {
        for (final entry in dates.entries) {
          stored.putIfAbsent(entry.key, () => encodeDate(entry.value));
        }
      });

  /// Copy the names and dates of everything at or beneath each old path in
  /// [moves] to the matching new path, for files and folders that have been
  /// copied.

  static Future<void> copy(Map<String, String> moves) =>
      _change((names, dates) {
        names.addAll(_moved(names, moves));
        dates.addAll(_moved(dates, moves));
      });

  /// Forget [paths], and everything beneath those that are folders, for items
  /// that have been deleted. Nothing that goes wrong is reported: a name left
  /// behind belongs to a path no file will ever have again.

  static Future<void> forget(Iterable<String> paths) async {
    final gone = paths.toList();
    if (gone.isEmpty) return;
    try {
      bool isGone(String path, _) => gone.any((each) => _within(path, each));
      await _change((names, dates) {
        names.removeWhere(isGone);
        dates.removeWhere(isGone);
      });
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

  static Future<void> _change(
    void Function(Map<String, String> names, Map<String, String> dates) edit,
  ) {
    final write = _writes.then((_) async {
      // A table that could not be read must not be written over with only
      // the change.

      await ensureLoaded();
      if (_loadedFrom != await _file.url()) {
        throw SecurityKeyNeeded(namesFileName);
      }

      final updated = Map<String, String>.from(_names);
      final dated = Map<String, String>.from(_dates);
      edit(updated, dated);
      if (mapEquals(updated, _names) && mapEquals(dated, _dates)) return;

      try {
        await _file.write(encodeNames(updated, dated));
      } on PodMediaException {
        rethrow;
      } on Object catch (e) {
        throw PodMediaException('The file names could not be saved: $e');
      }
      _names
        ..clear()
        ..addAll(updated);
      _dates
        ..clear()
        ..addAll(dated);
    });

    // The chain itself never carries a failure forward, or one refused write
    // would fail every write after it.

    _writes = write.then((_) {}, onError: (_) {});
    return write;
  }

  static Future<void> _load(String url) async {
    final content = await _file.read();
    _names
      ..clear()
      ..addAll(content == null ? const {} : decodeNames(content));
    _dates
      ..clear()
      ..addAll(content == null ? const {} : decodeDates(content));
    _loadedFrom = url;
  }
}
