/// Choose how items are laid out.
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

import 'package:photopod/models/view_prefs.dart';

/// Let the user choose the layout and the page size.
///
/// The choices are held on the device rather than in the Pod, because how
/// somebody likes to look at their album on a phone is rarely how they want
/// to look at it on a desktop.

Future<void> showViewOptionsDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const _ViewOptionsDialog(),
);

class _ViewOptionsDialog extends StatelessWidget {
  const _ViewOptionsDialog();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<ViewPrefs>();
    final labels = Theme.of(context).textTheme.labelLarge;

    return AlertDialog(
      title: const Text('View'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Layout', style: labels),
            const Gap(8),
            SegmentedButton<MediaViewMode>(
              segments: [
                for (final mode in MediaViewMode.values)
                  ButtonSegment(
                    value: mode,
                    icon: Icon(mode.icon),
                    label: Text(mode.label),
                  ),
              ],
              selected: {prefs.viewMode},
              onSelectionChanged: (selection) =>
                  prefs.setViewMode(selection.first),
            ),
            if (prefs.viewMode == MediaViewMode.grid) ...[
              const Gap(24),
              Text('Tile size', style: labels),
              const Gap(8),
              SegmentedButton<MediaTileSize>(
                segments: [
                  for (final size in MediaTileSize.values)
                    ButtonSegment(value: size, label: Text(size.label)),
                ],
                selected: {prefs.tileSize},
                onSelectionChanged: (selection) =>
                    prefs.setTileSize(selection.first),
              ),
            ],
            const Gap(24),
            Text('Items per page', style: labels),
            const Gap(8),
            Wrap(
              spacing: 8,
              children: [
                for (final size in pageSizeChoices)
                  ChoiceChip(
                    label: Text('$size'),
                    selected: prefs.itemsPerPage == size,
                    onSelected: (_) => prefs.setItemsPerPage(size),
                  ),
              ],
            ),
            const Gap(12),
            Text(
              'Tiles show the pictures alone, with no file names; the '
              'details of any one of them are a tap on Get Info away. Large '
              'albums are shown a page at a time so that the Pod is asked '
              'for only as many thumbnails as are on screen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
