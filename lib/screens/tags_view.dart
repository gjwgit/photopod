/// The Tags section: the photos in the album, grouped by what they show.
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

import 'package:flutter/material.dart';

import 'package:gap/gap.dart';
import 'package:provider/provider.dart';

import 'package:photopod/constants/analyser.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/view_prefs.dart';
import 'package:photopod/screens/analyser_section_view.dart';
import 'package:photopod/services/tags.dart';
import 'package:photopod/widgets/person_section.dart';
import 'package:photopod/widgets/tag_section.dart';

/// What Tags shows: every tag on the album's photos, and the photos the
/// Analyser has not looked at.

typedef TagsContent = ({List<TagEntry> tags, List<MediaItem> unprocessed});

/// The Tags section: every tag the Analyser has put on the album's photos,
/// those on the most photos first, each above a row of its photos, with a
/// row of categories along the top to narrow them down; then the photos not
/// yet looked at.
///
/// Opening the section sends nothing anywhere. Photos are tagged only when
/// the user asks, with Tag Photos, in the Library or here. See
/// [AnalyserSectionView].

class TagsView extends StatelessWidget {
  const TagsView({super.key});

  @override
  Widget build(BuildContext context) =>
      AnalyserSectionView<PhotoTags, TagsContent>(
        keyPrompt: 'Please enter your security key to see your photos\' tags',
        lookingFor: 'tags',
        contentOf: (tags, photos) => (
          tags: tags.tagsIn(photos),
          unprocessed: tags.unprocessedIn(photos),
        ),
        isEmpty: (content) =>
            content.tags.isEmpty && content.unprocessed.isEmpty,
        summary: (tags, content) {
          final count = content.tags.length;
          return '$count ${count == 1 ? 'tag' : 'tags'}, '
              '${content.unprocessed.length} photos not yet looked at';
        },
        errorTitle: 'Could not read the tags',
        emptyIcon: Icons.sell_outlined,
        emptyTitle: 'No photos yet',
        emptyText:
            'Add photos in the Library, then select some and tap Tag Photos '
            'to have the ${Analyser.displayName} say what they show.',
        builder: (context, tags, content, refresh) =>
            _TagList(tags: tags, content: content, onPreviewClosed: refresh),
      );
}

/// The tags, under a row of their categories, then the photos not yet
/// looked at. Choosing a category shows only its tags; choosing it again
/// shows them all.

class _TagList extends StatefulWidget {
  const _TagList({
    required this.tags,
    required this.content,
    required this.onPreviewClosed,
  });

  final PhotoTags tags;
  final TagsContent content;
  final VoidCallback onPreviewClosed;

  @override
  State<_TagList> createState() => _TagListState();
}

class _TagListState extends State<_TagList> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final extent = context.watch<ViewPrefs>().tileSize.extent;
    final entries = widget.content.tags;
    final unprocessed = widget.content.unprocessed;
    final categories = PhotoTags.categoriesOf(entries);
    final category = categories.contains(_category) ? _category : null;
    final shown = [
      for (final entry in entries)
        if (category == null || entry.category == category) entry,
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (categories.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                for (final name in categories) ...[
                  FilterChip(
                    avatar: Icon(categoryIcon(name), size: 18),
                    label: Text(name),
                    selected: name == category,
                    showCheckmark: false,
                    onSelected: (selected) =>
                        setState(() => _category = selected ? name : null),
                  ),
                  const Gap(8),
                ],
              ],
            ),
          ),
        for (final entry in shown)
          TagSection(
            key: ValueKey(entry.tag),
            entry: entry,
            tileExtent: extent,
          ),
        if (unprocessed.isNotEmpty && category == null)
          PersonSection(
            key: const ValueKey('unprocessed'),
            title: 'Unprocessed',
            icon: Icons.hourglass_empty,
            items: unprocessed,
            tileExtent: extent,
            onPreviewClosed: widget.onPreviewClosed,
            action: FilledButton.tonalIcon(
              icon: const Icon(Icons.sell_outlined),
              label: const Text('Tag Photos'),
              onPressed: widget.tags.isScanning
                  ? null
                  : () => askToAnalyse(
                      context,
                      widget.tags,
                      unprocessed,
                      action: 'Tag Photos',
                      finding: 'say what is shown in',
                    ),
            ),
          ),
      ],
    );
  }
}
