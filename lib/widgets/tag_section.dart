/// One tag in the Tags section, with every photo that carries it.
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

import 'package:photopod/dialogs/preview_dialog.dart';
import 'package:photopod/services/tags.dart';
import 'package:photopod/widgets/media_thumbnail.dart';

/// The icon of each category the Analyser files tags under, and of any
/// category it adds later.

IconData categoryIcon(String category) => switch (category) {
  'Nature' => Icons.landscape_outlined,
  'Places' => Icons.location_city_outlined,
  'People' => Icons.groups_outlined,
  'Animals' => Icons.pets_outlined,
  'Food and drink' => Icons.restaurant_outlined,
  'Things' => Icons.category_outlined,
  'Occasions' => Icons.celebration_outlined,
  'Documents' => Icons.description_outlined,
  yourTagsCategory => Icons.person_outline,
  _ => Icons.sell_outlined,
};

/// A tag's name, category and photo count, above a row of its photos that
/// scrolls sideways, as an album's does. A tap on a photo previews it, and
/// the preview steps through this tag's photos.

class TagSection extends StatelessWidget {
  const TagSection({super.key, required this.entry, required this.tileExtent});

  final TagEntry entry;

  /// The size of a tile, from the user's View preferences.

  final double tileExtent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = entry.items.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Tooltip(
                message: entry.category,
                child: Icon(
                  categoryIcon(entry.category),
                  color: theme.colorScheme.primary,
                ),
              ),
              const Gap(12),
              Flexible(
                child: Text(
                  entry.tag,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Gap(8),
              Text(
                '$count ${count == 1 ? 'photo' : 'photos'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const Gap(8),
          SizedBox(
            height: tileExtent,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: count,
              separatorBuilder: (context, index) => const Gap(4),
              itemBuilder: (context, index) {
                final item = entry.items[index];
                return SizedBox.square(
                  dimension: tileExtent,
                  child: Material(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () =>
                          showPreviewDialog(context, item, items: entry.items),
                      child: Tooltip(
                        message: item.name,
                        child: MediaThumbnail(item: item),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
