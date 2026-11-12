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

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:photopod/constants/analyser.dart';
import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/models/face_book.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/analyser_inbox.dart';
import 'package:photopod/services/analyser_section.dart';
import 'package:photopod/services/demo_library.dart';
import 'package:photopod/services/encrypted_json_file.dart';
import 'package:photopod/services/face_results.dart';
import 'package:photopod/services/media_catalog.dart';

part 'people_catalog.dart';
part 'people_demo.dart';

/// The faces file, encrypted on the Pod like the rest of PhotoPod's
/// bookkeeping: an embedding is as personal as the face it came from.

const _file = EncryptedJsonFile('faces.json');

/// One person as People lists them: someone named in the photos, by the
/// user or by the Analyser, or someone the Analyser found and no one has
/// named yet.

class PersonEntry {
  /// What People knows them by: a name, ignoring case, or for someone not
  /// yet named, their place in the faces file.

  final String id;
  final String? name;

  /// What they are shown as: their name, or Unknown and their alias.

  final String title;

  /// For someone not yet named, who they are in the faces file, so that
  /// naming them names every face the Analyser took for them.

  final String? person;

  /// The face that pictures them best, when the Analyser has found one, and
  /// the photo it is in.

  final FaceRecord? portrait;
  final MediaItem portraitItem;

  /// Every photo they are in, newest first.

  final List<MediaItem> items;

  const PersonEntry({
    required this.id,
    required this.name,
    required this.title,
    this.person,
    required this.portrait,
    required this.portraitItem,
    required this.items,
  });
}

/// The user's photos as People shows them: by person, those named first,
/// alphabetically, then those not yet named, most photos first; and the
/// photos the Analyser has not looked at.

typedef PeopleSections = ({
  List<PersonEntry> named,
  List<PersonEntry> unknown,
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
/// The faces themselves are found by the Analyser, through Pod sharing
/// alone, and only in the photos the user chooses ([analyse]): those photos
/// are left in the face inbox ([faceInbox]) for just as long as it takes;
/// see [AnalyserSection] for how.

class People extends AnalyserSection {
  People() : super(faceInbox);

  FaceBook _book = FaceBook();

  @override
  String get lookingFor => 'faces';

  @override
  int get scannedCount => _book.scanned.length;

  // Whether the faces are those of the sample album shown before login,
  // for the halves of this class in people_catalog.dart and
  // people_demo.dart.

  bool get _demo => isDemo;

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
    final unknown = <String, Map<String, MediaItem>>{};
    for (final face in _book.faces.values) {
      final item = byPath[face.path];
      final person = _book.people[face.person];
      if (item == null || person == null) continue;
      final name = person.name;
      if (name == null) {
        (unknown[person.id] ??= {})[item.path] = item;
      } else {
        file(name, item);
      }
    }

    final named = [
      for (final MapEntry(key: id, value: items) in photosOf.entries)
        _entry(id, spelt[id]!, AnalyserSection.newestFirst(items.values)),
    ]..sort((a, b) => a.id.compareTo(b.id));

    final unnamed = [
      for (final MapEntry(key: id, value: items) in unknown.entries)
        _unknownEntry(
          _book.people[id]!,
          AnalyserSection.newestFirst(items.values),
        ),
    ]..sort((a, b) => b.items.length.compareTo(a.items.length));

    return (named: named, unknown: unnamed, unprocessed: unprocessedIn(own));
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
      title: name,
      portrait: portrait,
      portraitItem: inItems[portrait?.path] ?? items.first,
      items: items,
    );
  }

  PersonEntry _unknownEntry(Person person, List<MediaItem> items) {
    final portrait = _book.portraitOf(person.id);
    return PersonEntry(
      id: 'unknown:${person.id}',
      name: null,
      title: person.label,
      person: person.id,
      portrait: portrait,
      portraitItem:
          items.where((item) => item.path == portrait?.path).firstOrNull ??
          items.first,
      items: items,
    );
  }

  /// The faces the Analyser found in the photo at [path] that no one has
  /// named yet, each with what it goes by meanwhile.

  List<({FaceRecord face, String label})> unnamedIn(String path) => [
    for (final face in _book.faces.values)
      if (face.path == path && _book.people[face.person]?.name == null)
        (face: face, label: _book.people[face.person]!.label),
  ];

  /// Name [person], someone the Analyser found, [name]: every face it took
  /// for them is named, in every photo they are in. When someone is already
  /// called [name], the two become one person.

  Future<void> namePerson(String person, String name) async {
    final given = name.trim();
    if (given.isEmpty || _book.people[person] == null) return;
    final same = _book.people.values
        .where(
          (other) =>
              other.id != person &&
              other.name?.toLowerCase() == given.toLowerCase(),
        )
        .firstOrNull;
    if (same != null) {
      _book.merge(person, same.id);
    } else {
      _book.people[person]!.name = given;
    }
    notifyListeners();
    await save();
    await _toCatalog(_book.photosOf([same?.id ?? person]));
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
    await save();

    if (!_demo) {
      try {
        await MediaCatalog.renamePerson(from, name);
      } on Object catch (e) {
        reportError('Could not rename $from: $e');
      }
      await _toCatalog(_book.photosOf(target == null ? renamed : [target.id]));
    }
    notifyListeners();
  }

  // -- The faces file and the Analyser's answers ---------------------------

  @override
  Future<void> readFile() async {
    final json = await _file.read();
    _book = json == null ? FaceBook() : FaceBook.fromJson(json);
  }

  @override
  Future<void> writeFile() => _file.write(_book.toJson());

  @override
  void clear() => _book = FaceBook();

  @override
  bool hasLookedAt(String path) => _book.hasScanned(path);

  @override
  Iterable<String> get knownPaths => {
    ..._book.scanned,
    for (final f in _book.faces.values) f.path,
  };

  @override
  bool retainOnly(Set<String> paths) => _book.retainOnly(paths);

  @override
  void removePhoto(String path) => _book.removePhoto(path);

  @override
  bool fileAnswer(String path, String content, {String? url}) {
    final answer = FaceResult.parse(content);
    if (answer == null) return false;
    _book.addPhoto(path, answer.faces, url: url);
    return answer.failed != null;
  }

  // A face found where the user has named someone in Get Info takes that
  // name, and the people named in the photos are listed in the catalog.

  @override
  Future<Set<String>> fromCatalog() => _nameFromCatalog();

  @override
  Future<void> toCatalog(Iterable<String> paths) => _toCatalog(paths);

  @override
  Future<void> lookAtSamples(List<MediaItem> todo) => _scanSamples(todo);

  // For the halves of this class in people_catalog.dart and
  // people_demo.dart, which cannot call the protected method themselves.

  void _changed() => notifyListeners();
}
