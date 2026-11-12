/// What the Analyser answers for a photo left in the tag inbox.
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

/// Which model and vocabulary the tags come from. PhotoPod stores this
/// beside the tags it keeps, and tags every photo afresh when it changes.
/// It must match `Vocabulary.model_id` in the analyser's tagger.py.

const String tagModelId = 'siglip-b16-webli:tags-v1';

/// One tag on one photo: what it is, the category it is filed under, and
/// how sure the Analyser was, from 0 to 1.

typedef FoundTag = ({String tag, String category, double score});

/// What the Analyser found for one photo left in the tag inbox, read from
/// the `<key>.tags.enc.ttl` it wrote beside the photo:
///
///     {"format": "photopod-tag-result", "version": 1, "model": ...,
///      "analysed": ..., "width": w, "height": h, "tags": [...]}
///
/// or, for a photo it could not read, `"failed": "<why>"` in place of the
/// tags. See analyser/face_analyser/face_analyser/service.py.

class TagResult {
  /// The tags, best first, empty when none fits or the photo [failed].

  final List<FoundTag> tags;

  /// Why the photo could not be read, or null when it was.

  final String? failed;

  const TagResult(this.tags, [this.failed]);

  /// The result [content] holds, or null when it is not one, or comes from
  /// another model or vocabulary. Such a photo is simply looked at again.

  static TagResult? parse(String content) {
    try {
      final json = jsonDecode(content);
      if (json is! Map<String, dynamic>) return null;
      if (json['format'] != 'photopod-tag-result') return null;
      if (json['model'] != tagModelId) return null;
      final failed = json['failed'];
      if (failed != null) return TagResult(const [], '$failed');
      return TagResult(parseFoundTags(json['tags'] as List? ?? const []));
    } on Object catch (e) {
      debugPrint('PhotoPod: not a tag result: $e');
      return null;
    }
  }
}

/// The tags in [tags], as the Analyser lists them and the tags file keeps
/// them.

List<FoundTag> parseFoundTags(List<dynamic> tags) => [
  for (final tag in tags.cast<Map<String, dynamic>>())
    (
      tag: tag['tag'] as String,
      category: tag['category'] as String? ?? '',
      score: (tag['score'] as num? ?? 0).toDouble(),
    ),
];

/// [tags] as the tags file keeps them.

List<Map<String, Object>> foundTagsToJson(List<FoundTag> tags) => [
  for (final t in tags)
    {'tag': t.tag, 'category': t.category, 'score': t.score},
];
