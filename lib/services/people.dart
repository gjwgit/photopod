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

import 'package:flutter/services.dart' show rootBundle;

import 'package:photopod/models/face_book.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/analyser_inbox.dart';
import 'package:photopod/services/analyser_section.dart';
import 'package:photopod/services/demo_library.dart';
import 'package:photopod/services/encrypted_json_file.dart';
import 'package:photopod/services/face_results.dart';

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
/// The faces file in the Pod, `faces.json.enc.ttl`, is the record of every
/// photo already looked at, kept in [FaceBook] form (for each person their
/// name, their portrait and the photos they are in; for each face where it
/// is, a small picture of it and its embedding). The faces themselves are
/// found by the Analyser through the face inbox ([faceInbox]); see
/// [AnalyserSection] for how.

class People extends AnalyserSection {
  People() : super(faceInbox);

  FaceBook _book = FaceBook();

  @override
  String get lookingFor => 'faces';

  @override
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

  /// Call [person] by [name], or forget their name when it is blank.

  Future<void> rename(String person, String name) async {
    final entry = _book.people[person];
    if (entry == null) return;
    entry.name = name.trim().isEmpty ? null : name.trim();
    notifyListeners();
    await save();
  }

  /// Treat [from] and [into] as one person, keeping [into].

  Future<void> merge(String from, String into) async {
    _book.merge(from, into);
    notifyListeners();
    await save();
  }

  // -- The faces file ------------------------------------------------------

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

  @override
  Future<void> lookAtSamples(List<MediaItem> todo) => _scanSamples(todo);
}
