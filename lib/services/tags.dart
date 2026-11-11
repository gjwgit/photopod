/// The tags on the photos in the album, worked out by the Analyser.
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

import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/analyser_inbox.dart';
import 'package:photopod/services/analyser_section.dart';
import 'package:photopod/services/demo_library.dart';
import 'package:photopod/services/encrypted_json_file.dart';
import 'package:photopod/services/tag_results.dart';

/// The tags file, encrypted on the Pod like the rest of PhotoPod's
/// bookkeeping: what a photo shows says as much as the photo.
///
///     {"version": 1, "model": "<tagModelId>",
///      "photos": {"<Pod-relative path>": [{"tag": "Beach",
///                 "category": "Nature", "score": 0.98}]}}
///
/// A photo looked at that fits no tag is kept with an empty list, so that it
/// is not looked at again.

const _file = EncryptedJsonFile('tags.json');

/// What the Analyser found for each sample photo, worked out once with
/// `./run.sh analyse` (see analyser/face_analyser/README.md) and shipped
/// with the app.

const _demoTagsAsset = 'assets/demo/tags.json';

/// One tag as Tags lists it, with every photo that carries it, the surest
/// first.

class TagEntry {
  final String tag;
  final String category;
  final List<MediaItem> items;

  const TagEntry({
    required this.tag,
    required this.category,
    required this.items,
  });
}

/// Tags the user's own photos with what they show, such as Beach, Dog or
/// Receipt, each filed under a category such as Nature, Animals or
/// Documents. The tags come from the Analyser through the tag inbox
/// ([tagInbox]), turned on and off apart from People's; see
/// [AnalyserSection] for how.

class PhotoTags extends AnalyserSection {
  PhotoTags() : super(tagInbox);

  Map<String, List<FoundTag>> _photos = {};

  @override
  String get lookingFor => 'tags';

  @override
  int get scannedCount => _photos.length;

  /// The tags on the photo at [path], best first.

  List<FoundTag> tagsOf(String path) => _photos[path] ?? const [];

  /// Every tag on the photos in [photos], those on the most photos first.

  List<TagEntry> tagsIn(List<MediaItem> photos) {
    final byPath = {for (final item in photos) item.path: item};
    final found = <String, ({String category, List<(MediaItem, double)> on})>{};

    for (final MapEntry(key: path, value: tags) in _photos.entries) {
      final item = byPath[path];
      if (item == null) continue;
      for (final t in tags) {
        found.putIfAbsent(t.tag, () => (category: t.category, on: [])).on.add((
          item,
          t.score,
        ));
      }
    }

    final entries = [
      for (final MapEntry(key: tag, value: v) in found.entries)
        TagEntry(
          tag: tag,
          category: v.category,
          items: [
            for (final (item, _) in v.on..sort((a, b) => b.$2.compareTo(a.$2)))
              item,
          ],
        ),
    ];
    entries.sort((a, b) {
      final count = b.items.length.compareTo(a.items.length);
      return count != 0 ? count : a.tag.compareTo(b.tag);
    });
    return entries;
  }

  /// The categories of [entries], those with the most photos first.

  static List<String> categoriesOf(List<TagEntry> entries) {
    final counts = <String, int>{};
    for (final entry in entries) {
      counts[entry.category] =
          (counts[entry.category] ?? 0) + entry.items.length;
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  // -- The tags file -------------------------------------------------------

  @override
  Future<void> readFile() async {
    final text = await _file.read();
    _photos = {};
    if (text == null) return;
    final json = jsonDecode(text) as Map<String, dynamic>;

    // Tags from another model or vocabulary are not comparable with those
    // coming now, so every photo is tagged afresh.

    if (json['model'] != tagModelId) return;
    _photos = {
      for (final MapEntry(key: path, value: tags)
          in (json['photos'] as Map<String, dynamic>? ?? const {}).entries)
        path: parseFoundTags(tags as List),
    };
  }

  @override
  Future<void> writeFile() => _file.write(
    jsonEncode({
      'version': 1,
      'model': tagModelId,
      'photos': {
        for (final MapEntry(key: path, value: tags) in _photos.entries)
          path: foundTagsToJson(tags),
      },
    }),
  );

  @override
  void clear() => _photos = {};

  @override
  bool hasLookedAt(String path) => _photos.containsKey(path);

  @override
  Iterable<String> get knownPaths => _photos.keys;

  @override
  bool retainOnly(Set<String> paths) {
    final before = _photos.length;
    _photos.removeWhere((path, _) => !paths.contains(path));
    return _photos.length != before;
  }

  @override
  void removePhoto(String path) => _photos.remove(path);

  @override
  bool fileAnswer(String path, String content, {String? url}) {
    final answer = TagResult.parse(content);
    if (answer == null) return false;
    _photos[path] = answer.tags;
    return answer.failed != null;
  }

  @override
  Future<void> lookAtSamples(List<MediaItem> todo) async {
    final data =
        jsonDecode(await rootBundle.loadString(_demoTagsAsset))
            as Map<String, dynamic>;
    final tags = {
      for (final entry in (data['tags'] as Map<String, dynamic>).entries)
        DemoLibrary.pathOf(entry.key): parseFoundTags(entry.value as List),
    };
    for (final item in todo) {
      _photos[item.path] = tags[item.path] ?? const [];
    }
  }
}
