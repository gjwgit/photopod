/// The thumbnail grid of photos, videos and folders.
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

import 'package:photopod/models/media_item.dart';
import 'package:photopod/widgets/media_thumbnail.dart';

/// Lay [items] out as thumbnails, with the name beneath each one.
///
/// The grid sizes itself to the available width so the same code works from a
/// phone through to a wide desktop window. Names longer than a tile are cut
/// short with an ellipsis rather than wrapped, so every tile keeps the same
/// height and the grid stays a grid.

class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.isSelected,
    required this.onTap,
    required this.onActivate,
  });

  /// The folders and files on the current page.

  final List<MediaItem> items;

  /// Whether an item is part of the current selection.

  final bool Function(MediaItem) isSelected;

  /// Called on a single tap, which changes the selection.

  final void Function(MediaItem) onTap;

  /// Called on a double tap, which opens a folder or previews a file.

  final void Function(MediaItem) onActivate;

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(16),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 180,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.82,
    ),
    itemCount: items.length,
    itemBuilder: (context, index) {
      final item = items[index];
      return _MediaTile(
        item: item,
        selected: isSelected(item),
        onTap: () => onTap(item),
        onActivate: () => onActivate(item),
      );
    },
  );
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onActivate,
  });

  final MediaItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: item.name,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onDoubleTap: onActivate,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected ? scheme.primaryContainer : null,
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    color: scheme.surfaceContainerHighest,
                    child: MediaThumbnail(item: item),
                  ),
                ),
              ),
              const Gap(6),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected ? scheme.onPrimaryContainer : null,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
