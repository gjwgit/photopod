/// The random names photos, videos and folders are stored under, and the
/// table of the names the user gave them that came before the catalog.
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
import 'dart:math';

import 'package:photopod/constants/media.dart';

/// The name of the table of names, at the top of the album, stored encrypted
/// as `names.json.enc.ttl`. It kept the name and date of each item until the
/// catalog took over, and is now only read, once, to build the catalog; see
/// `MediaCatalog`.

const String namesFileName = 'names.json';

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
/// lives in `MediaCatalog` like a file's.

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
