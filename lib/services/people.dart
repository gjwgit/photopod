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

import 'package:flutter/foundation.dart';

import 'package:photopod/models/face_book.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/encrypted_json_file.dart';
import 'package:photopod/services/face_engine.dart';
import 'package:photopod/services/media_renditions.dart';
import 'package:photopod/services/thumbnail_cache.dart';

/// The fewest photos someone must be in before People lists them. One
/// sighting is as likely to be a passer-by as a friend; a named person is
/// listed whatever their count.

const int minPhotosPerPerson = 2;

/// How many photos are looked at between saves, so that an interrupted scan
/// loses little and a long one does not rewrite the file after every photo.

const int _saveEvery = 25;

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
/// Everything happens on this device. Each photo's large rendition is fed
/// to [FaceEngine], and what comes out is kept, in [FaceBook] form, in the
/// encrypted `faces.json.enc.ttl` beside the album: for each person their
/// name, their portrait and the photos they are in, by path and URL; for
/// each face where it is, a small picture of it and its embedding. Another
/// device therefore picks up where this one left off, and only new photos
/// are looked at.

class People extends ChangeNotifier {
  FaceBook _book = FaceBook();
  bool _loaded = false;
  bool _scanning = false;
  bool _cancelled = false;
  int _done = 0;
  int _toDo = 0;
  int _failed = 0;
  String? _status;
  String? _error;

  /// Whether this platform can recognise faces at all.

  bool get isSupported => FaceEngine.isSupported;

  bool get isScanning => _scanning;

  /// How far the current scan has got.

  int get done => _done;
  int get toDo => _toDo;

  /// How many photos the last scan could not read.

  int get failed => _failed;

  /// What the scan is doing other than looking at photos, such as
  /// downloading the models.

  String? get status => _status;

  String? get error => _error;

  /// How many of the user's photos have been looked at.

  int get scannedCount => _book.scanned.length;

  /// Everyone found in [photos], the user's photos as the album index has
  /// them, those in the most photos first.

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

  Future<void> load() async {
    if (_loaded) return;
    final json = await _file.read();
    _book = json == null ? FaceBook() : FaceBook.fromJson(json);
    _loaded = true;
    notifyListeners();
  }

  /// Look for faces in every photo in [photos] not yet looked at.
  ///
  /// With [prune], photos no longer in [photos] are forgotten, which is how
  /// deleted photos leave People; it is left off when the album index is
  /// incomplete, so that a truncated walk does not forget anyone.

  Future<void> scan(List<MediaItem> photos, {bool prune = true}) async {
    if (_scanning || !isSupported) return;
    _scanning = true;
    _cancelled = false;
    _error = null;
    _failed = 0;
    _done = 0;
    _toDo = 0;
    notifyListeners();

    try {
      await load();

      final own = photos.where((item) => item.isPhoto && !item.isShared);
      var changed = prune && _book.retainOnly({for (final i in own) i.path});

      final todo = own.where((item) => !_book.hasScanned(item.path)).toList();
      _toDo = todo.length;
      notifyListeners();
      if (todo.isEmpty) return;

      await FaceEngine.start(
        onStatus: (status) {
          _status = status;
          notifyListeners();
        },
      );
      _status = null;

      for (final item in todo) {
        if (_cancelled) break;
        try {
          final image =
              await MediaRenditions.readLarge(item) ??
              await ThumbnailCache.instance.preview(item);
          if (image == null) throw StateError('no picture');
          _book.addPhoto(
            item.path,
            await FaceEngine.analyse(image),
            url: item.url,
          );
          changed = true;
        } on Object catch (e) {
          _failed++;
          debugPrint('PhotoPod: could not look for faces in ${item.url}: $e');
        }
        _done++;
        if (_cancelled) break;
        if (_done % _saveEvery == 0 && changed) {
          await _save();
          changed = false;
        }
        notifyListeners();
      }

      if (changed && !_cancelled) await _save();
    } on Object catch (e) {
      _error = '$e';
      debugPrint('PhotoPod: face scan stopped: $e');
    } finally {
      _status = null;
      _scanning = false;
      notifyListeners();
    }
  }

  /// Call [person] by [name], or forget their name when it is blank.

  Future<void> rename(String person, String name) async {
    final entry = _book.people[person];
    if (entry == null) return;
    entry.name = name.trim().isEmpty ? null : name.trim();
    notifyListeners();
    await _save();
  }

  /// Treat [from] and [into] as one person, keeping [into].

  Future<void> merge(String from, String into) async {
    _book.merge(from, into);
    notifyListeners();
    await _save();
  }

  /// Forget [path]'s faces and look at it again on the next scan, for a
  /// photo that has been replaced.

  void forgetPhoto(String path) {
    _book.removePhoto(path);
    notifyListeners();
  }

  /// Forget everything, as on logout, so nothing is left for the next user.

  void reset() {
    _cancelled = true;
    _book = FaceBook();
    _loaded = false;
    FaceEngine.stop();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await _file.write(_book.toJson());
    } on Object catch (e) {
      _error = 'Could not save the faces found: $e';
      debugPrint('PhotoPod: $_error');
    }
  }
}
