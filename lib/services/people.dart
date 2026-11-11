/// The people in the album, found by recognising their faces.
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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:solidpod/solidpod.dart' show isUserLoggedIn;

import 'package:photopod/constants/face_analyser.dart';
import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/models/face_book.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/demo_library.dart';
import 'package:photopod/services/encrypted_json_file.dart';
import 'package:photopod/services/face_inbox.dart';
import 'package:photopod/services/face_results.dart';
import 'package:photopod/services/media_catalog.dart';
import 'package:photopod/services/media_renditions.dart';
import 'package:photopod/services/thumbnail_cache.dart';

part 'people_analyser.dart';
part 'people_catalog.dart';
part 'people_demo.dart';

/// The fewest photos someone must be in before People lists them. One
/// sighting is as likely to be a passer-by as a friend; a named person is
/// listed whatever their count.

const int minPhotosPerPerson = 2;

/// The faces file, encrypted on the Pod like the rest of PhotoPod's
/// bookkeeping: an embedding is as personal as the face it came from.

const _file = EncryptedJsonFile('faces.json');

/// One person as People lists them.

class PersonEntry {
  final String id;
  final String? name;

  /// The face that pictures them best, and the photo it is in.

  final FaceRecord portrait;
  final MediaItem portraitItem;

  /// Every photo they are in, newest first.

  final List<MediaItem> items;

  const PersonEntry({
    required this.id,
    required this.name,
    required this.portrait,
    required this.portraitItem,
    required this.items,
  });
}

/// Finds the faces in the user's own photos and groups them into people.
///
/// The faces file in the Pod, `faces.json.enc.ttl`, is read first, as soon
/// as the security key is to hand: it is the record of every photo already
/// looked at, kept in [FaceBook] form (for each person their name, their
/// portrait and the photos they are in; for each face where it is, a small
/// picture of it and its embedding).
///
/// The faces themselves are found by the Analyser, entirely between Pods on
/// the Solid server: each photo not yet in the faces file is left in the
/// face inbox ([FaceInbox]), a folder of the user's Pod shared only with the
/// Analyser, and the Analyser writes what it found back into the same
/// folder. Each answer is filed here and saved to the faces file before it
/// is deleted. Photos added while People is on are left in the inbox as
/// they are added, and their answers looked out for.
///
/// Deleting a photo deletes its faces from the file too ([forget]), and
/// takes it out of the inbox if it is still waiting there.

class People extends ChangeNotifier {
  People() {
    // An answer is filed under the photo its key stands for, so a photo
    // left as it is added has to be known by its key, or its answer would
    // wait for a scan of People.

    _added = FaceInbox.added.listen((path) {
      _pathOf[faceKeyOf(path)] = path;
      _soon();
    });
  }

  FaceBook _book = FaceBook();
  bool _loaded = false;
  Future<void>? _loading;
  late final StreamSubscription<String> _added;
  Timer? _debounce;

  // Whether the faces are those of the sample album shown before login,
  // which are kept in memory only.

  bool _demo = false;
  bool _scanning = false;
  bool _cancelled = false;

  // The photos deleted while a scan is running, which it must not file
  // again if their results arrive afterwards.

  final Set<String> _forgotten = {};

  // The path of each photo by its key in the inbox and in the results, for
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

  /// Whether People has to be turned on, sharing the face inbox with the
  /// Analyser, before any photo can be looked at.

  bool get needsConsent => _needsConsent;

  /// How many of the user's photos have been looked at.

  int get scannedCount => _book.scanned.length;

  List<PersonEntry> peopleIn(List<MediaItem> photos) {
    final byPath = {for (final item in photos) item.path: item};
    final entries = <PersonEntry>[];

    for (final person in _book.people.values) {
      final faces = _book.facesOf(person.id);
      final paths = {for (final face in faces) face.path};
      final items = [
        for (final path in paths)
          if (byPath[path] != null) byPath[path]!,
      ];
      if (items.isEmpty) continue;
      if (person.name == null && items.length < minPhotosPerPerson) continue;

      final portrait = _book.portraitOf(person.id)!;
      items.sort(
        (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
      );
      entries.add(
        PersonEntry(
          id: person.id,
          name: person.name,
          portrait: portrait,
          portraitItem: byPath[portrait.path] ?? items.first,
          items: items,
        ),
      );
    }

    entries.sort((a, b) {
      final named = (a.name == null ? 1 : 0) - (b.name == null ? 1 : 0);
      return named != 0 ? named : b.items.length - a.items.length;
    });
    return entries;
  }

  /// Read the faces file, once per login.
  ///
  /// Reading needs the security key, and throws [SecurityKeyNeeded] when it
  /// has not been entered; the next call tries again.

  Future<void> load() => _loading ??= _load().whenComplete(() {
    _loading = null;
  });

  /// [load], for a caller that only wants the faces in hand early, such as
  /// the album once the security key is entered, and has nothing to do
  /// about a failure: the People section reads the file again and reports.

  Future<void> preload() async {
    try {
      await load();
    } on Object catch (e) {
      debugPrint('PhotoPod: could not read the faces file yet: $e');
    }
  }

  Future<void> _load() async {
    // Logging in or out swaps the sample album for a Pod or back, and the
    // faces found in one mean nothing in the other.

    final demo = !await isUserLoggedIn();
    if (demo != _demo) {
      _book = FaceBook();
      _loaded = false;
      _demo = demo;
    }
    if (_loaded) return;
    if (!_demo) {
      final json = await _file.read();
      _book = json == null ? FaceBook() : FaceBook.fromJson(json);
    }
    _loaded = true;
    notifyListeners();
  }

  /// Find the faces in every photo in [photos] not yet looked at.
  ///
  /// With [prune], photos no longer in [photos] are forgotten, which is how
  /// photos deleted elsewhere leave People; it is left off when the album
  /// index is incomplete, so that a truncated walk does not forget anyone.

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
        _pathOf[faceKeyOf(item.path)] = item.path;
        _urlOf[item.path] = item.url;
      }
      final changed = prune && _book.retainOnly({for (final i in own) i.path});

      // Names given in Get Info since the last scan name the people found.

      final named = await _nameFromCatalog();
      if (changed || named.isNotEmpty) await _save();
      await _toCatalog(named);

      final todo = own.where((item) => !_book.hasScanned(item.path)).toList();
      _knowsAll = prune;
      if (_demo) {
        await _scanSamples(todo);
      } else {
        await _scanWithAnalyser(todo);
      }
    } on Object catch (e) {
      _error = '$e';
      debugPrint('PhotoPod: face scan stopped: $e');
    } finally {
      _status = null;
      _scanning = false;
      _knowsAll = false;
      notifyListeners();
    }
  }

  /// Turn People on: share the face inbox with the Analyser, then scan.

  Future<void> enable() async {
    await FaceInbox.enable();
    _needsConsent = false;
    notifyListeners();
  }

  /// Turn People off: stop sharing the face inbox and empty it. The people
  /// already found stay.

  Future<void> disable() async {
    _cancelled = true;
    await FaceInbox.disable();
    _waiting = 0;
    _needsConsent = true;
    notifyListeners();
  }

  /// Call [person] by [name], or forget their name when it is blank.

  Future<void> rename(String person, String name) async {
    final entry = _book.people[person];
    if (entry == null) return;
    entry.name = name.trim().isEmpty ? null : name.trim();
    notifyListeners();
    await _save();
    await _toCatalog(_book.photosOf([person]));
  }

  /// Treat [from] and [into] as one person, keeping [into].

  Future<void> merge(String from, String into) async {
    _book.merge(from, into);
    notifyListeners();
    await _save();
    await _toCatalog(_book.photosOf([into]));
  }

  /// Delete the faces of the photos in [items], and of every photo in the
  /// folders among them, from the faces file in the Pod, as when they are
  /// deleted, and take them out of the face inbox if they are waiting there.
  ///
  /// The file is read first if it has not been yet. When it cannot be, as
  /// when the security key has not been entered, the faces stay until the
  /// next scan, which forgets every photo no longer in the album.

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
      debugPrint('PhotoPod: faces of deleted photos kept until next scan: $e');
      return;
    }

    final known = {
      ..._book.scanned,
      for (final f in _book.faces.values) f.path,
      ..._pathOf.values,
    };
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
        await FaceInbox.remove(remove);
      } on Object catch (e) {
        debugPrint('PhotoPod: could not empty the face inbox: $e');
      }
    }
    remove.forEach(_book.removePhoto);
    notifyListeners();
    await _save();
  }

  /// Forget everything, as on logout, so nothing is left for the next user.

  void reset() {
    _cancelled = true;
    _debounce?.cancel();
    _book = FaceBook();
    _loaded = false;
    _error = null;
    _needsConsent = false;
    _pathOf.clear();
    _urlOf.clear();
    _waiting = 0;
    FaceInbox.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_added.cancel());
    super.dispose();
  }

  // For the halves of this class in people_analyser.dart and
  // people_demo.dart, which cannot call the protected method themselves.

  void _changed() => notifyListeners();

  Future<void> _save() async {
    if (_demo) return;
    try {
      await _file.write(_book.toJson());
    } on Object catch (e) {
      _error = 'Could not save the faces found: $e';
      debugPrint('PhotoPod: $_error');
    }
  }
}
