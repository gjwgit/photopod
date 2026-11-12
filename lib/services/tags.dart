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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:photopod/constants/analyser.dart';
import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/analyser_inbox.dart';
import 'package:photopod/services/analyser_section.dart';
import 'package:photopod/services/demo_library.dart';
import 'package:photopod/services/encrypted_json_file.dart';
import 'package:photopod/services/media_catalog.dart';
import 'package:photopod/services/tag_results.dart';

/// The tags file, encrypted on the Pod like the rest of PhotoPod's
/// bookkeeping: what a photo shows says as much as the photo.
///
///     {"version": 1, "model": "<tagModelId>",
///      "photos": {"<Pod-relative path>": [{"tag": "Beach",
///                 "category": "Nature", "score": 0.98}]},
///      "catalogued": ["<Pod-relative path>"]}
///
/// A photo looked at that fits no tag is kept with an empty list, so that it
/// is not looked at again. `catalogued` lists the photos whose tags are in
/// the catalog too, where Get Info shows them; a file from before it was
/// kept has every photo's tags put there on the next scan.

const _file = EncryptedJsonFile('tags.json');

/// What the Analyser found for each sample photo, worked out once with
/// `./run.sh analyse` (see analyser/face_analyser/README.md) and shipped
/// with the app.

const _demoTagsAsset = 'assets/demo/tags.json';

/// The category Tags files the user's own tags under, those they add in Get
/// Info.

const String yourTagsCategory = 'Your tags';

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
/// ([tagInbox]), and only for the photos the user chooses with Tag Photos;
/// see [AnalyserSection] for how.
///
/// Every tag found is also put in the photo's catalog entry, as suggested by
/// [Analyser.source], so that Get Info shows it beside the user's own and
/// the filter finds it. The catalog then has the last word: a tag the user
/// takes off a photo there leaves it here too, and a tag they add there is
/// listed here under [yourTagsCategory].

class PhotoTags extends AnalyserSection {
  PhotoTags() : super(tagInbox) {
    _catalogChanges = MediaCatalog.changes.listen((_) => notifyListeners());
  }

  Map<String, List<FoundTag>> _photos = {};

  // The photos whose tags are in the catalog as well.

  Set<String> _catalogued = {};

  late final StreamSubscription<void> _catalogChanges;

  @override
  String get lookingFor => 'tags';

  @override
  int get scannedCount => _photos.length;

  /// The tags the Analyser found on the photo at [path], best first.

  List<FoundTag> tagsOf(String path) => _photos[path] ?? const [];

  /// Every tag on the photos in [photos], those on the most photos first.

  List<TagEntry> tagsIn(List<MediaItem> photos) {
    final found = <String, ({String category, List<(MediaItem, double)> on})>{};
    void add(String tag, String category, MediaItem item, double score) => found
        .putIfAbsent(tag, () => (category: category, on: []))
        .on
        .add((item, score));

    for (final item in photos) {
      final entry = isDemo ? null : MediaCatalog.entryOf(item.path);

      // Once the tags are in the catalog, those the user has taken off
      // there are no longer shown.

      final kept = _catalogued.contains(item.path) && entry != null
          ? {for (final tag in entry.tags) tag.label.toLowerCase()}
          : null;
      final shown = <String>{};
      for (final t in tagsOf(item.path)) {
        if (kept != null && !kept.contains(t.tag.toLowerCase())) continue;
        add(t.tag, t.category, item, t.score);
        shown.add(t.tag.toLowerCase());
      }
      for (final tag in entry?.tags ?? const <PhotoTag>[]) {
        if (tag.source != userSource) continue;
        if (!shown.add(tag.label.toLowerCase())) continue;
        add(tag.label, yourTagsCategory, item, 1);
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
    clear();
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
    _catalogued = {
      for (final path in json['catalogued'] as List? ?? const [])
        if (path is String && _photos.containsKey(path)) path,
    };
  }

  @override
  Future<void> writeFile() async {
    await _catalogue();
    await _file.write(
      jsonEncode({
        'version': 1,
        'model': tagModelId,
        'photos': {
          for (final MapEntry(key: path, value: tags) in _photos.entries)
            path: foundTagsToJson(tags),
        },
        'catalogued': _catalogued.toList()..sort(),
      }),
    );
  }

  // Put the tags of every photo not yet catalogued in the catalog, in one
  // write. A failure, as without the security key, leaves them to the next
  // save: the tags file is still worth writing.

  Future<void> _catalogue() async {
    final pending = {
      for (final MapEntry(key: path, value: tags) in _photos.entries)
        if (!_catalogued.contains(path))
          path: [
            for (final t in tags)
              PhotoTag(t.tag, source: Analyser.source, confidence: t.score),
          ],
    };
    if (pending.isEmpty) return;
    try {
      await MediaCatalog.suggestTags(pending, Analyser.source);
      _catalogued.addAll(pending.keys);
    } on Object catch (e) {
      debugPrint('PhotoPod: tags not put in the catalog yet: $e');
    }
  }

  @override
  bool get hasUnsaved => _photos.keys.any((p) => !_catalogued.contains(p));

  @override
  void clear() {
    _photos = {};
    _catalogued = {};
  }

  @override
  bool hasLookedAt(String path) => _photos.containsKey(path);

  @override
  Iterable<String> get knownPaths => _photos.keys;

  @override
  bool retainOnly(Set<String> paths) {
    final before = _photos.length;
    _photos.removeWhere((path, _) => !paths.contains(path));
    _catalogued.retainAll(_photos.keys);
    return _photos.length != before;
  }

  @override
  void removePhoto(String path) {
    _photos.remove(path);
    _catalogued.remove(path);
  }

  @override
  bool fileAnswer(String path, String content, {String? url}) {
    final answer = TagResult.parse(content);
    if (answer == null) return false;
    _photos[path] = answer.tags;

    // New tags replace in the catalog what the Analyser suggested before.

    _catalogued.remove(path);
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

  @override
  void dispose() {
    unawaited(_catalogChanges.cancel());
    super.dispose();
  }
}
