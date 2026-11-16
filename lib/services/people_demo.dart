/// People for the sample album shown before login.
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

part of 'people.dart';

/// What the Analyser found in each sample photo, worked out once with
/// `./run.sh analyse --full` (see analyser/face_analyser/README.md) and
/// shipped with the app. A visitor who has not logged in has no Pod to share
/// an inbox from, and the samples are the same for everyone.

const _demoFacesAsset = 'assets/demo/faces.json';

/// People for the sample album shown before login, from the faces worked out
/// in advance, so that a visitor sees what People does without a Pod.

extension _PeopleDemo on People {
  Future<void> _scanSamples(List<MediaItem> todo) async {
    final data =
        jsonDecode(await rootBundle.loadString(_demoFacesAsset))
            as Map<String, dynamic>;
    final faces = {
      for (final entry in (data['faces'] as Map<String, dynamic>).entries)
        DemoLibrary.pathOf(entry.key): parseFoundFaces(entry.value as List),
    };
    for (final item in todo) {
      _book.addPhoto(item.path, faces[item.path] ?? const [], url: item.url);
    }
    _nameSamples();
  }

  // Name each person found in the samples after whoever is known to be in
  // most of their photos, and fold together two found to be the same
  // person, as the owner of an album would tidy it. The search itself knows
  // nothing of the names: they are only put on what it found.

  void _nameSamples() {
    final named = <String, String>{};
    final found = _book.people.values.toList()
      ..sort(
        (a, b) =>
            _book.facesOf(b.id).length.compareTo(_book.facesOf(a.id).length),
      );

    for (final person in found) {
      final paths = {for (final face in _book.facesOf(person.id)) face.path};
      final counts = <String, int>{};
      for (final path in paths) {
        for (final who in DemoLibrary.peopleAt(path)) {
          counts[who] = (counts[who] ?? 0) + 1;
        }
      }
      if (counts.isEmpty) continue;

      // Only a clear majority names anyone. A face from a photo of two
      // people, found on its own, could be either of them.

      final ranked = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final best = ranked.first;
      if (best.value * 2 <= paths.length) continue;
      if (ranked.length > 1 && ranked[1].value == best.value) continue;

      final into = named[best.key];
      if (into != null) {
        _book.merge(person.id, into);
        continue;
      }
      person.name ??= best.key;
      named[best.key] = person.id;
    }
  }
}
