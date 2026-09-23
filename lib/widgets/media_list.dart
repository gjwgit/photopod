/// The detailed list of photos, videos and folders.
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

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/utils/formatting.dart';
import 'package:photopod/widgets/media_thumbnail.dart';

/// Lay [items] out one per row, with size and date alongside the name.
///
/// The detailed view is the one to reach for when the name matters more than
/// the picture: it still shows a small thumbnail, but it puts the file size
/// and the date the server last recorded a change where they can be read and
/// compared down the column.

class MediaList extends StatelessWidget {
  const MediaList({
    super.key,
    required this.items,
    required this.isSelected,
    required this.isFavourite,
    required this.onTap,
    required this.onActivate,
    required this.onToggleFavourite,
  });

  /// The folders and files on the current page.

  final List<MediaItem> items;

  /// Whether an item is part of the current selection.

  final bool Function(MediaItem) isSelected;

  /// Whether an item carries a heart.

  final bool Function(MediaItem) isFavourite;

  /// Called on a single tap, which changes the selection.

  final void Function(MediaItem) onTap;

  /// Called on a double tap, which opens a folder or previews a file.

  final void Function(MediaItem) onActivate;

  /// Called when the heart beside a row is tapped.

  final void Function(MediaItem) onToggleFavourite;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 640;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        final selected = isSelected(item);
        final scheme = Theme.of(context).colorScheme;

        return ListTile(
          selected: selected,
          selectedTileColor: scheme.primaryContainer,
          onTap: () => onTap(item),
          leading: SizedBox(
            width: 48,
            height: 48,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                color: scheme.surfaceContainerHighest,
                child: MediaThumbnail(item: item),
              ),
            ),
          ),
          title: GestureDetector(
            onDoubleTap: () => onActivate(item),
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          subtitle: wide ? null : Text(_details(item)),
          trailing: SizedBox(
            width: wide ? 300 : 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (wide) ...[
                  Expanded(
                    child: Text(
                      _kindLabel(item),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      item.isFolder ? '' : formatBytes(item.size),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const Gap(12),
                  SizedBox(
                    width: 120,
                    child: Text(
                      formatDateTime(item.modified),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                if (!item.isFolder)
                  IconButton(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    tooltip: isFavourite(item)
                        ? 'Remove from Favourites'
                        : 'Add to Favourites',
                    icon: Icon(
                      isFavourite(item)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: isFavourite(item) ? const Color(0xFFE53935) : null,
                    ),
                    onPressed: () => onToggleFavourite(item),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _kindLabel(MediaItem item) {
    if (item.isFolder) return 'Folder';
    final ext = extensionOf(item.name).toUpperCase();
    return ext.isEmpty ? 'File' : '$ext file';
  }

  static String _details(MediaItem item) => [
    _kindLabel(item),
    if (!item.isFolder && item.size != null) formatBytes(item.size),
    formatDateTime(item.modified),
  ].join('  ·  ');
}
