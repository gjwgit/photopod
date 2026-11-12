/// What People and Tags share: a section fed by an inbox the Analyser answers.
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

import 'package:solidpod/solidpod.dart' show isUserLoggedIn;

import 'package:photopod/constants/analyser.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/analyser_inbox.dart';
import 'package:photopod/services/media_renditions.dart';
import 'package:photopod/services/thumbnail_cache.dart';

part 'analyser_section_scan.dart';

/// A section of the album whose contents the Analyser works out: People,
/// from the faces in the photos, and Tags, from what they show.
///
/// What has been worked out already is kept in an encrypted file in the
/// Pod, read first, as soon as the security key is to hand: it is the record
/// of every photo already looked at.
///
/// Photos are looked at only when the user asks ([analyse]), with Identify
/// People or Tag Photos: those photos are left in the section's inbox, a
/// folder of the user's Pod shared with the Analyser for just as long as it
/// takes, and the Analyser writes what it found back into the same folder.
/// Each answer is filed here and saved to the file before it is deleted.
/// Opening the section sends nothing ([refresh]).
///
/// Deleting a photo deletes what was found in it from the file too
/// ([forget]), and takes it out of the inbox if it is still waiting there.

abstract class AnalyserSection extends ChangeNotifier {
  AnalyserSection(this.inbox);

  /// The inbox this section's photos are left in.

  final AnalyserInbox inbox;

  bool _loaded = false;
  Future<void>? _loading;

  // The photos chosen to be looked at and not yet left in the inbox. More
  // can be chosen while a look is under way, and join it.

  final List<MediaItem> _queue = [];

  // Whether what is shown is the sample album shown before login, kept in
  // memory only.

  bool _demo = false;
  bool _scanning = false;
  bool _cancelled = false;

  // The photos deleted while a look is under way, which it must not file
  // again if their answers arrive afterwards.

  final Set<String> _forgotten = {};

  // The path of each photo by its key in the inbox and in the answers, for
  // the photos this session knows of.

  final Map<String, String> _pathOf = {};
  final Map<String, String> _urlOf = {};

  int _done = 0;
  int _toDo = 0;
  int _failed = 0;
  int _waiting = 0;
  String? _status;
  String? _error;

  // -- What each section supplies -----------------------------------------

  /// What the Analyser looks for, for messages: "faces", "tags".

  @protected
  String get lookingFor;

  /// Read the section's file from the Pod, or start afresh when there is
  /// none. Throws [SecurityKeyNeeded] without the security key.

  @protected
  Future<void> readFile();

  /// Write the section's file to the Pod.

  @protected
  Future<void> writeFile();

  /// Forget everything held in memory.

  @protected
  void clear();

  /// Whether the photo at [path] has been looked at.

  @protected
  bool hasLookedAt(String path);

  /// Every photo path the section holds anything for.

  @protected
  Iterable<String> get knownPaths;

  /// Forget the photos not in [paths], returning whether any went.

  @protected
  bool retainOnly(Set<String> paths);

  /// Forget the photo at [path].

  @protected
  void removePhoto(String path);

  /// File the Analyser's answer [content] for the photo at [path], returning
  /// whether the Analyser could not read the photo. An answer this app
  /// cannot use is passed over, and the photo can be asked about again.

  @protected
  bool fileAnswer(String path, String content, {String? url});

  /// Whether the section holds something not yet saved, such as work a
  /// file from an earlier version still needs, which [refresh] saves.

  @protected
  bool get hasUnsaved => false;

  /// Take on what the user has said in Get Info since, returning the photos
  /// whose entries changed. Called by [refresh] and after answers are filed.

  @protected
  Future<Set<String>> fromCatalog() async => const {};

  /// Tell the catalog what was found in the photos at [paths], once saved.

  @protected
  Future<void> toCatalog(Iterable<String> paths) async {}

  /// File what is known in advance for the sample photos in [todo].

  @protected
  Future<void> lookAtSamples(List<MediaItem> todo);

  // -- State ---------------------------------------------------------------

  /// Whether the section shows the sample album rather than a Pod.

  @protected
  bool get isDemo => _demo;

  /// Whether photos are being looked at, or the file read.

  bool get isScanning => _scanning;

  /// How far the current look has got leaving photos for the Analyser.

  int get done => _done;
  int get toDo => _toDo;

  /// How many photos are waiting in the inbox for the Analyser.

  int get waiting => _waiting;

  /// How many photos the last look could not read.

  int get failed => _failed;

  /// What the look is doing, for the status line.

  String? get status => _status;

  String? get error => _error;

  /// How many of the user's photos have been looked at.

  int get scannedCount;

  /// The user's own photos among [photos] not yet looked at, newest first.

  List<MediaItem> unprocessedIn(List<MediaItem> photos) => newestFirst(
    photos.where(
      (item) => item.isPhoto && !item.isShared && !hasLookedAt(item.path),
    ),
  );

  /// [items] with the most recently taken first.

  static List<MediaItem> newestFirst(Iterable<MediaItem> items) =>
      items.toList()..sort(
        (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
      );

  // -- Reading -------------------------------------------------------------

  /// Read the file, once per login.
  ///
  /// Reading needs the security key, and throws [SecurityKeyNeeded] when it
  /// has not been entered; the next call tries again.

  Future<void> load() => _loading ??= _load().whenComplete(() {
    _loading = null;
  });

  /// [load], for a caller that only wants the file in hand early, such as
  /// the album once the security key is entered, and has nothing to do
  /// about a failure: the section reads the file again and reports.

  Future<void> preload() async {
    try {
      await load();
    } on Object catch (e) {
      debugPrint('PhotoPod: could not read the $lookingFor file yet: $e');
    }
  }

  Future<void> _load() async {
    // Logging in or out swaps the sample album for a Pod or back, and what
    // was found in one means nothing in the other.

    final demo = !await isUserLoggedIn();
    if (demo != _demo) {
      clear();
      _loaded = false;
      _demo = demo;
    }
    if (_loaded) return;
    if (_demo) {
      clear();
    } else {
      await readFile();
    }
    _loaded = true;
    notifyListeners();
  }

  // -- Asking --------------------------------------------------------------

  /// Bring the section up to date with the album, [photos], as when it is
  /// opened: read the file, take on what was said in Get Info since, and
  /// finish a look at some photos that was cut short, as by the app being
  /// closed. Nothing new is sent to the Analyser; see [analyse].
  ///
  /// With [prune], photos no longer in [photos] are forgotten, which is how
  /// photos deleted elsewhere leave the section; it is left off when the
  /// album index is incomplete, so that a truncated walk forgets nothing.

  Future<void> refresh(List<MediaItem> photos, {bool prune = true}) async {
    if (_scanning) return;
    _begin();

    try {
      await load();

      final own = photos
          .where((item) => item.isPhoto && !item.isShared)
          .toList();
      _know(own);
      final changed = prune && retainOnly({for (final i in own) i.path});

      final named = await fromCatalog();
      if (changed || named.isNotEmpty || (hasUnsaved && !_demo)) {
        await save();
      }
      await toCatalog(named);

      if (!_demo && await inbox.exists()) await _finishEarlier();
    } on Object catch (e) {
      _error = '$e';
      debugPrint('PhotoPod: $lookingFor could not be brought up to date: $e');
    } finally {
      _end();
    }
  }

  /// Have the Analyser look at [photos], the user's own photos among them,
  /// whether or not they have been looked at before. The inbox is shared
  /// with the Analyser for the look and no longer, and photos chosen while a
  /// look is under way join it.

  Future<void> analyse(Iterable<MediaItem> photos) async {
    final own = [
      for (final item in photos)
        if (item.isPhoto && !item.isShared) item,
    ];
    if (own.isEmpty) return;
    _know(own);

    if (_scanning) {
      _queue.addAll(own);
      _toDo += own.length;
      notifyListeners();
      return;
    }

    _begin();
    _queue.addAll(own);
    _toDo = own.length;
    try {
      await load();
      if (_demo) {
        await lookAtSamples(own);
        _queue.clear();
      } else {
        await _runAnalyser();
      }
    } on Object catch (e) {
      _error = '$e';
      debugPrint('PhotoPod: the $lookingFor were not found: $e');
    } finally {
      _end();
    }
  }

  // Remember which photo each key in the inbox stands for.

  void _know(List<MediaItem> photos) {
    for (final item in photos) {
      _pathOf[inboxKeyOf(item.path)] = item.path;
      _urlOf[item.path] = item.url;
    }
  }

  void _begin() {
    _scanning = true;
    _cancelled = false;
    _forgotten.clear();
    _error = null;
    _status = null;
    _failed = 0;
    _done = 0;
    _toDo = 0;
    notifyListeners();
  }

  void _end() {
    _queue.clear();
    _scanning = false;
    notifyListeners();
  }

  // -- Forgetting ----------------------------------------------------------

  /// Delete what was found in the photos in [items], and in every photo in
  /// the folders among them, from the file in the Pod, as when they are
  /// deleted, and take them out of the inbox if they are waiting there.
  ///
  /// The file is read first if it has not been yet. When it cannot be, as
  /// when the security key has not been entered, what was found stays until
  /// the next refresh, which forgets every photo no longer in the album.

  Future<void> forget(Iterable<MediaItem> items) async {
    final gone = {
      for (final item in items)
        if (!item.isFolder) item.path,
    };
    final prefixes = [
      for (final item in items)
        if (item.isFolder) '${item.path}/',
    ];
    if (gone.isEmpty && prefixes.isEmpty) return;
    _forgotten.addAll(gone);

    try {
      await load();
    } on Object catch (e) {
      debugPrint('PhotoPod: $lookingFor of deleted photos kept for now: $e');
      return;
    }

    final known = {...knownPaths, ..._pathOf.values};
    final remove = known
        .where(
          (path) =>
              gone.contains(path) || prefixes.any((p) => path.startsWith(p)),
        )
        .toSet();
    if (remove.isEmpty) return;
    _forgotten.addAll(remove);
    if (!_demo) {
      try {
        await inbox.remove(remove);
      } on Object catch (e) {
        debugPrint('PhotoPod: could not empty the ${inbox.label}: $e');
      }
    }
    remove.forEach(removePhoto);
    notifyListeners();
    await save();
  }

  /// Forget everything, as on logout, so nothing is left for the next user.

  void reset() {
    _cancelled = true;
    _queue.clear();
    clear();
    _loaded = false;
    _error = null;
    _pathOf.clear();
    _urlOf.clear();
    _waiting = 0;
    notifyListeners();
  }

  /// Report [message] as what went wrong, in the section's status.

  @protected
  void reportError(String message) {
    _error = message;
    notifyListeners();
  }

  /// Write the file, unless the section shows the samples, reporting a
  /// failure rather than throwing.

  @protected
  Future<void> save() async {
    if (_demo) return;
    try {
      await writeFile();
    } on Object catch (e) {
      _error = 'Could not save the $lookingFor found: $e';
      debugPrint('PhotoPod: $_error');
    }
  }

  // For the half of this class in analyser_section_scan.dart, which cannot
  // call the protected method itself.

  void _changed() => notifyListeners();
}
