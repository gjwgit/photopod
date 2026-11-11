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

/// A section of the album whose contents the Analyser works out, one photo
/// at a time, through an [AnalyserInbox]: People, from the faces in the
/// photos, and Tags, from what they show.
///
/// What has been worked out already is kept in an encrypted file in the
/// Pod, read first, as soon as the security key is to hand: it is the record
/// of every photo already looked at. Each photo not yet in it is left in the
/// inbox, a folder of the user's Pod shared only with the Analyser, and the
/// Analyser writes what it found back into the same folder. Each answer is
/// filed here and saved to the file before it is deleted. Photos added while
/// the section is on are left in the inbox as they are added, and their
/// answers looked out for.
///
/// Deleting a photo deletes what was found in it from the file too
/// ([forget]), and takes it out of the inbox if it is still waiting there.
///
/// Each section has its own inbox, turned on and off on its own.

abstract class AnalyserSection extends ChangeNotifier {
  AnalyserSection(this.inbox) {
    _added = inbox.added.listen((_) => _soon());
  }

  /// The inbox this section's photos are left in.

  final AnalyserInbox inbox;

  bool _loaded = false;
  Future<void>? _loading;
  late final StreamSubscription<void> _added;
  Timer? _debounce;

  // Whether what is shown is the sample album shown before login, kept in
  // memory only.

  bool _demo = false;
  bool _scanning = false;
  bool _cancelled = false;

  // The photos deleted while a scan is running, which it must not file
  // again if their answers arrive afterwards.

  final Set<String> _forgotten = {};

  // The path of each photo by its key in the inbox and in the answers, for
  // the photos this session knows of.

  final Map<String, String> _pathOf = {};
  final Map<String, String> _urlOf = {};

  // Whether [_pathOf] holds every photo in the album, as during a scan of a
  // complete album index.

  bool _knowsAll = false;

  int _done = 0;
  int _toDo = 0;
  int _failed = 0;
  int _waiting = 0;
  String? _status;
  String? _error;
  bool _needsConsent = false;

  // -- What each section supplies -----------------------------------------

  /// What the Analyser looks for, for the status line: "faces", "tags".

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
  /// cannot use is passed over, and the photo looked at again later.

  @protected
  bool fileAnswer(String path, String content, {String? url});

  /// Whether the section holds something not yet saved, such as work a
  /// file from an earlier version still needs, which a scan saves first.

  @protected
  bool get hasUnsaved => false;

  /// File what is known in advance for the sample photos in [todo].

  @protected
  Future<void> lookAtSamples(List<MediaItem> todo);

  // -- State ---------------------------------------------------------------

  /// Whether the section shows the sample album rather than a Pod.

  @protected
  bool get isDemo => _demo;

  bool get isScanning => _scanning;

  /// How far the current scan has got leaving photos for the Analyser.

  int get done => _done;
  int get toDo => _toDo;

  /// How many photos are waiting in the inbox for the Analyser.

  int get waiting => _waiting;

  /// How many photos the last scan could not read.

  int get failed => _failed;

  /// What the scan is doing, for the status line.

  String? get status => _status;

  String? get error => _error;

  /// Whether the section has to be turned on, sharing its inbox with the
  /// Analyser, before any photo can be looked at.

  bool get needsConsent => _needsConsent;

  /// How many of the user's photos have been looked at.

  int get scannedCount;

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

  // -- Scanning ------------------------------------------------------------

  /// Look at every photo in [photos] not yet looked at.
  ///
  /// With [prune], photos no longer in [photos] are forgotten, which is how
  /// photos deleted elsewhere leave the section; it is left off when the
  /// album index is incomplete, so that a truncated walk forgets nothing.

  Future<void> scan(List<MediaItem> photos, {bool prune = true}) async {
    if (_scanning) return;
    _scanning = true;
    _cancelled = false;
    _forgotten.clear();
    _error = null;
    _needsConsent = false;
    _failed = 0;
    _done = 0;
    _toDo = 0;
    notifyListeners();

    try {
      await load();

      final own = photos
          .where((item) => item.isPhoto && !item.isShared)
          .toList();
      for (final item in own) {
        _pathOf[inboxKeyOf(item.path)] = item.path;
        _urlOf[item.path] = item.url;
      }
      if ((prune && retainOnly({for (final i in own) i.path})) ||
          (hasUnsaved && !_demo)) {
        await save();
      }

      final todo = own.where((item) => !hasLookedAt(item.path)).toList();
      _knowsAll = prune;
      if (_demo) {
        await lookAtSamples(todo);
      } else {
        await _scanWithAnalyser(todo);
      }
    } on Object catch (e) {
      _error = '$e';
      debugPrint('PhotoPod: $lookingFor scan stopped: $e');
    } finally {
      _status = null;
      _scanning = false;
      _knowsAll = false;
      notifyListeners();
    }
  }

  /// Turn the section on: share its inbox with the Analyser.

  Future<void> enable() async {
    await inbox.enable();
    _needsConsent = false;
    notifyListeners();
  }

  /// Turn the section off: stop sharing its inbox and empty it. What has
  /// been found already stays.

  Future<void> disable() async {
    _cancelled = true;
    await inbox.disable();
    _waiting = 0;
    _needsConsent = true;
    notifyListeners();
  }

  /// Delete what was found in the photos in [items], and in every photo in
  /// the folders among them, from the file in the Pod, as when they are
  /// deleted, and take them out of the inbox if they are waiting there.
  ///
  /// The file is read first if it has not been yet. When it cannot be, as
  /// when the security key has not been entered, what was found stays until
  /// the next scan, which forgets every photo no longer in the album.

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
    _debounce?.cancel();
    clear();
    _loaded = false;
    _error = null;
    _needsConsent = false;
    _pathOf.clear();
    _urlOf.clear();
    _waiting = 0;
    inbox.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_added.cancel());
    super.dispose();
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
