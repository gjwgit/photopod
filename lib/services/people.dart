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

/// The faces file, encrypted on the Pod like the rest of PhotoPod's
/// bookkeeping: an embedding is as personal as the face it came from.

const _file = EncryptedJsonFile('faces.json');

/// One person as People lists them: someone named in the photos, by the
/// user or by the Analyser.

class PersonEntry {
  /// What People knows them by: their name, ignoring case.

  final String id;
  final String? name;

  /// The face that pictures them best, when the Analyser has found one, and
  /// the photo it is in.

  final FaceRecord? portrait;
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

/// The user's photos as People shows them: those with someone named in
/// them, by person, alphabetically; those with a face no one has named; and
/// those the Analyser has not looked at.

typedef PeopleSections = ({
  List<PersonEntry> named,
  List<MediaItem> unknown,
  List<MediaItem> unprocessed,
});

/// Finds the faces in the user's own photos and groups them into people.
///
/// The faces file in the Pod, `faces.json.enc.ttl`, is read first, as soon
/// as the security key is to hand: it is the record of every photo already
/// looked at, kept in [FaceBook] form (for each person their name, their
/// portrait and the photos they are in; for each face where it is, a small
/// picture of it and its embedding).
///
/// The faces themselves are found by the Analyser, entirely between Pods on
/// the Solid server, and only in the photos the user chooses ([analyse]):
/// those photos are left in the face inbox ([FaceInbox]), a folder of the
/// user's Pod shared with the Analyser for just as long as it takes, and the
/// Analyser writes what it found back into the same folder. Each answer is
/// filed here and saved to the faces file before it is deleted.
///
/// Deleting a photo deletes its faces from the file too ([forget]), and
/// takes it out of the inbox if it is still waiting there.

class People extends ChangeNotifier {
  FaceBook _book = FaceBook();
  bool _loaded = false;
  Future<void>? _loading;

  // The photos chosen to be looked at and not yet left in the inbox. More
  // can be chosen while a look is under way, and join it.

  final List<MediaItem> _queue = [];

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

  int _done = 0;
  int _toDo = 0;
  int _failed = 0;
  int _waiting = 0;
  String? _status;
  String? _error;

  /// Whether photos are being looked at, or the faces file read.

  bool get isScanning => _scanning;

  /// How far the current look has got leaving photos for the Analyser.

  int get done => _done;
  int get toDo => _toDo;

  /// How many photos are waiting in the inbox for the Analyser.

  int get waiting => _waiting;

  /// How many photos the last scan could not read.

  int get failed => _failed;

  /// What the scan is doing, for the status line.

  String? get status => _status;

  String? get error => _error;

  /// How many of the user's photos have been looked at.

  int get scannedCount => _book.scanned.length;

  /// The user's own photos among [photos], arranged as People shows them.
  ///
  /// Who is in a photo is what the catalog says, whoever said it, so that a
  /// name given in Get Info counts as much as one the Analyser suggested.
  /// The faces file adds the names of the samples, which have no catalog,
  /// and of anyone the catalog has yet to be told of.

  PeopleSections sectionsOf(List<MediaItem> photos) {
    final own = [
      for (final item in photos)
        if (item.isPhoto && !item.isShared) item,
    ];
    final byPath = {for (final item in own) item.path: item};

    // Each person's photos, by their name ignoring case, as first spelt.

    final spelt = <String, String>{};
    final photosOf = <String, Map<String, MediaItem>>{};
    void file(String name, MediaItem item) {
      final id = name.toLowerCase();
      spelt.putIfAbsent(id, () => name);
      (photosOf[id] ??= {})[item.path] = item;
    }

    for (final item in own) {
      for (final face in MediaCatalog.entryOf(item.path)?.faces ?? const []) {
        file(face.name, item);
      }
    }
    final unknown = <String, MediaItem>{};
    for (final face in _book.faces.values) {
      final item = byPath[face.path];
      if (item == null) continue;
      final name = _book.people[face.person]?.name;
      if (name == null) {
        unknown[item.path] = item;
      } else {
        file(name, item);
      }
    }

    final named = [
      for (final MapEntry(key: id, value: items) in photosOf.entries)
        _entry(id, spelt[id]!, _newestFirst(items.values)),
    ]..sort((a, b) => a.id.compareTo(b.id));

    return (
      named: named,
      unknown: _newestFirst(unknown.values),
      unprocessed: _newestFirst(
        own.where((item) => !_book.hasScanned(item.path)),
      ),
    );
  }

  // The entry for the person called [name], pictured by the clearest face
  // the Analyser found of anyone by that name, if it found one.

  PersonEntry _entry(String id, String name, List<MediaItem> items) {
    final inItems = {for (final item in items) item.path: item};
    FaceRecord? portrait;
    for (final person in _book.people.values) {
      if (person.name?.toLowerCase() != id) continue;
      final face = _book.portraitOf(person.id);
      if (face != null && inItems.containsKey(face.path)) {
        if (portrait == null || face.area > portrait.area) portrait = face;
      }
    }
    return PersonEntry(
      id: id,
      name: name,
      portrait: portrait,
      portraitItem: inItems[portrait?.path] ?? items.first,
      items: items,
    );
  }

  static List<MediaItem> _newestFirst(Iterable<MediaItem> items) =>
      items.toList()..sort(
        (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
      );

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

  /// Bring People up to date with the album, [photos], as when People is
  /// opened: read the faces file, take on names given in Get Info since, and
  /// finish a look at some photos that was cut short, as by the app being
  /// closed. Nothing new is sent to the Analyser; see [analyse].
  ///
  /// With [prune], photos no longer in [photos] are forgotten, which is how
  /// photos deleted elsewhere leave People; it is left off when the album
  /// index is incomplete, so that a truncated walk does not forget anyone.

  Future<void> refresh(List<MediaItem> photos, {bool prune = true}) async {
    if (_scanning) return;
    _begin();

    try {
      await load();

      final own = photos
          .where((item) => item.isPhoto && !item.isShared)
          .toList();
      _know(own);
      final changed = prune && _book.retainOnly({for (final i in own) i.path});

      // Names given in Get Info since the last look name the people found.

      final named = await _nameFromCatalog();
      if (changed || named.isNotEmpty) await _save();
      await _toCatalog(named);

      if (!_demo && await FaceInbox.exists()) await _finishEarlier();
    } on Object catch (e) {
      _error = '$e';
      debugPrint('PhotoPod: People could not be brought up to date: $e');
    } finally {
      _end();
    }
  }

  /// Have the Analyser find the faces in [photos], the user's own photos
  /// among them, whether or not they have been looked at before. The inbox
  /// is shared with the Analyser for the look and no longer, and photos
  /// chosen while a look is under way join it.

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
        await _scanSamples(own);
        _queue.clear();
      } else {
        await _runAnalyser();
      }
    } on Object catch (e) {
      _error = '$e';
      debugPrint('PhotoPod: the people in the photos were not found: $e');
    } finally {
      _end();
    }
  }

  // Remember which photo each key in the inbox stands for.

  void _know(List<MediaItem> photos) {
    for (final item in photos) {
      _pathOf[faceKeyOf(item.path)] = item.path;
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

  /// The faces the Analyser found in the photo at [path] that no one has
  /// named yet.

  List<FaceRecord> unnamedIn(String path) => [
    for (final face in _book.faces.values)
      if (face.path == path && _book.people[face.person]?.name == null) face,
  ];

  /// Say [face] is [name]. The Analyser filed it with the faces it took for
  /// the same person, so they are all named, in every photo they are in;
  /// when someone is already called [name], the two become one person.

  Future<void> nameFace(FaceRecord face, String name) async {
    final given = name.trim();
    if (given.isEmpty || _book.people[face.person] == null) return;
    final same = _book.people.values
        .where(
          (person) =>
              person.id != face.person &&
              person.name?.toLowerCase() == given.toLowerCase(),
        )
        .firstOrNull;
    if (same != null) {
      _book.merge(face.person, same.id);
    } else {
      _book.people[face.person]!.name = given;
    }
    notifyListeners();
    await _save();
    await _toCatalog(_book.photosOf([same?.id ?? face.person]));
    notifyListeners();
  }

  /// Call the person named [from] [to] instead, in every photo they are in,
  /// however they were named. Naming them after someone else makes the two
  /// one person.

  Future<void> renamePerson(String from, String to) async {
    final name = to.trim();
    if (name.isEmpty || name == from) return;
    final old = from.toLowerCase();

    final target = _book.people.values
        .where(
          (person) =>
              person.name?.toLowerCase() == name.toLowerCase() &&
              person.name?.toLowerCase() != old,
        )
        .firstOrNull;
    final renamed = [
      for (final person in _book.people.values)
        if (person.name?.toLowerCase() == old) person.id,
    ];
    for (final id in renamed) {
      if (target != null) {
        _book.merge(id, target.id);
      } else {
        _book.people[id]!.name = name;
      }
    }
    notifyListeners();
    await _save();

    if (!_demo) {
      try {
        await MediaCatalog.renamePerson(from, name);
      } on Object catch (e) {
        _error = 'Could not rename $from: $e';
      }
      await _toCatalog(_book.photosOf(target == null ? renamed : [target.id]));
    }
    notifyListeners();
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
    _queue.clear();
    _book = FaceBook();
    _loaded = false;
    _error = null;
    _pathOf.clear();
    _urlOf.clear();
    _waiting = 0;
    notifyListeners();
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
