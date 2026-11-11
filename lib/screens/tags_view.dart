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
import 'package:photopod/models/view_prefs.dart';
import 'package:photopod/screens/analyser_section_view.dart';
import 'package:photopod/services/tags.dart';
import 'package:photopod/widgets/tag_section.dart';

/// The Tags section: every tag the Analyser has put on the album's photos,
/// those on the most photos first, each above a row of its photos, with a
/// row of categories along the top to narrow them down.
///
/// Nothing is shared until the user turns Tags on here, which shares the
/// tag inbox, and only that, with the Analyser; People has an inbox of its
/// own, turned on apart. See [AnalyserSectionView].

class TagsView extends StatelessWidget {
  const TagsView({super.key});

  @override
  Widget build(BuildContext context) =>
      AnalyserSectionView<PhotoTags, TagEntry>(
        name: 'Tags',
        icon: Icons.sell_outlined,
        offIcon: Icons.label_off_outlined,
        consentTitle: 'Sort your photos by what they show',
        consentText:
            'Tags are worked out by the ${Analyser.displayName}. Only one '
            'folder of your Pod is shared with it, and every photo in it '
            'stays encrypted. The Analyser opens a photo only to see what it '
            'shows, keeps no copy, and returns its tags to your Pod, '
            'encrypted. Nothing else in your Pod is shared, and you can turn '
            'Tags off at any time, which ends the share.',
        keyPrompt: 'Please enter your security key to tag your photos',
        lookingFor: 'tags',
        entriesOf: (tags, photos) => tags.tagsIn(photos),
        summary: (tags, count) => count == 0
            ? 'No tags yet'
            : '$count ${count == 1 ? 'tag' : 'tags'} on '
                  '${tags.scannedCount} photos looked at',
        emptyText:
            'A photo is tagged when the ${Analyser.displayName} is sure '
            'what it shows.',
        builder: (context, tags, entries) => _TagList(entries: entries),
      );
}

/// The tags, under a row of their categories. Choosing a category shows
/// only its tags; choosing it again shows them all.

class _TagList extends StatefulWidget {
  const _TagList({required this.entries});

  final List<TagEntry> entries;

  @override
  State<_TagList> createState() => _TagListState();
}

class _TagListState extends State<_TagList> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final extent = context.watch<ViewPrefs>().tileSize.extent;
    final categories = PhotoTags.categoriesOf(widget.entries);
    final category = categories.contains(_category) ? _category : null;
    final shown = [
      for (final entry in widget.entries)
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
      ],
    );
  }
}
