/// People and the catalog: who is in each photo, as Get Info shows it.
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
/// Authors: Graham Williams

part of 'people.dart';

/// The catalog is where PhotoPod records who is in each photo: Get Info
/// shows and edits it, and the filter bar searches it. People keeps its own
/// faces file for what only it needs (each face's embedding and picture,
/// and the people not yet named), and the two meet here, both ways:
///
/// * A name the user gave in Get Info names the person whose face is there,
///   so that People starts from what the user has already said.
/// * Each named person is listed in the catalog for the photos they are in,
///   credited to [Analyser.source], so that Get Info shows them as a
///   suggestion and the filter finds them. The user's own names always
///   stand; see [withFoundFaces].

extension _PeopleCatalog on People {
  /// Name the people not yet named after the names the user gave their
  /// photos in Get Info, returning the photos of anyone so named.

  Future<Set<String>> _nameFromCatalog() async {
    if (_demo) return const {};
    try {
      await MediaCatalog.ensureLoaded();
    } on Object catch (e) {
      debugPrint('PhotoPod: could not read the catalog for names: $e');
      return const {};
    }
    final given = {
      for (final entry in MediaCatalog.entries)
        if (entry.faces.any((face) => face.source == userSource))
          entry.path: [
            for (final face in entry.faces)
              if (face.source == userSource) face,
          ],
    };
    final named = _book.nameFrom(given);
    if (named.isEmpty) return const {};
    _changed();
    return _book.photosOf(named);
  }

  /// List the named people in the photos at [paths] in the catalog. A
  /// failure is only logged: the faces file still holds them, and the next
  /// change to the same photos lists them again.

  Future<void> _toCatalog(Iterable<String> paths) async {
    if (_demo) return;
    final found = _book.namedFaces(paths, Analyser.source);
    if (found.isEmpty) return;
    try {
      await MediaCatalog.setFoundFaces(Analyser.source, found);
    } on Object catch (e) {
      debugPrint(
        'PhotoPod: could not list the people found in the catalog: $e',
      );
    }
  }
}
