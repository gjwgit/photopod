/// The names of the files other people have shared with the user.
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

import 'package:flutter/foundation.dart';

import 'package:photopod/services/encrypted_json_file.dart';
import 'package:photopod/services/media_names.dart'
    show decodeNames, encodeNames;

/// The file the names are remembered in, at the top of the user's own album.
/// Its name is fixed and says nothing about what it holds, and its contents
/// are encrypted like every other piece of PhotoPod's bookkeeping.

const String sharedNamesFileName = 'shared-names.json';

const EncryptedJsonFile _file = EncryptedJsonFile(sharedNamesFileName);

/// How long to wait after a name is learnt before storing the table, so that
/// a page of thumbnails arriving together costs one write rather than one
/// each.

const Duration _saveAfter = Duration(seconds: 3);

/// The name each shared file's owner gave it, keyed by the file's URL.
///
/// A shared file sits in its owner's Pod under a random name, and the name
/// the owner gave it is inside the file, encrypted with the photo itself. It
/// is learnt here whenever the file is read and decrypted, for a thumbnail, a
/// preview or a download, and remembered in the user's own Pod so that the
/// next session can show it before the file has been read again. Reading the
/// file again picks up any rename the owner has made since.
///
/// The table is a [ChangeNotifier] so that whatever shows shared files can
/// show the real name as soon as it is known.

class SharedNames extends ChangeNotifier {
  SharedNames._();

  /// The single table the whole app shares.

  static final SharedNames instance = SharedNames._();

  final Map<String, String> _names = <String, String>{};

  // The URL the table was read from, so that logging in as someone else reads
  // theirs, and the read in progress, so that callers arriving together share
  // one request.

  String? _loadedFrom;
  Future<void>? _loading;
  bool _dirty = false;
  Timer? _saveTimer;

  /// The name the owner gave the shared file at [url], or null when it is
  /// not known yet.

  String? nameOf(String url) => _names[url];

  /// Read the remembered names from the Pod, once per session and user.
  ///
  /// Without the security key the table cannot be read, and nothing is
  /// remembered until it can be, but names learnt meanwhile still show.

  Future<void> ensureLoaded() async {
    final url = await _file.url();
    if (_loadedFrom == url) return;
    final loading = _loading ??= _load(url);
    try {
      await loading;
    } on SecurityKeyNeeded catch (e) {
      debugPrint('PhotoPod: shared file names not read yet: $e');
    } on Object catch (e) {
      debugPrint('PhotoPod: could not read the shared file names: $e');
    } finally {
      if (identical(_loading, loading)) _loading = null;
    }
  }

  /// Note that the shared file at [url] is called [name], as found inside it.

  void learn(String url, String name) {
    if (_names[url] == name) return;
    _names[url] = name;
    _dirty = true;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveAfter, () => unawaited(_save()));
  }

  Future<void> _load(String url) async {
    // Names learnt under another login belong to that user's table.

    if (_loadedFrom != null) {
      _saveTimer?.cancel();
      _names.clear();
      _dirty = false;
    }

    final content = await _file.read();
    final stored = content == null ? <String, String>{} : decodeNames(content);

    // A name learnt while the table was being read is newer than the one the
    // table holds.

    for (final entry in stored.entries) {
      _names.putIfAbsent(entry.key, () => entry.value);
    }
    _loadedFrom = url;
    notifyListeners();
  }

  // Store the table, but only once it has been read: writing it unread would
  // throw away every name remembered in earlier sessions.

  Future<void> _save() async {
    if (!_dirty) return;
    await ensureLoaded();
    if (_loadedFrom != await _file.url()) return;
    try {
      _dirty = false;
      await _file.write(encodeNames(_names));
    } on Object catch (e) {
      _dirty = true;
      debugPrint('PhotoPod: could not save the shared file names: $e');
    }
  }
}
