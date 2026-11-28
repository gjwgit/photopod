/// One group in the People section: a person, or the photos with no one
/// named, or those not yet looked at, with every photo in it.
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
import 'package:photopod/services/people.dart';
import 'package:photopod/widgets/face_avatar.dart';
import 'package:photopod/widgets/media_grid.dart';

/// How the tiles in the rows of People and Tags are selected and opened,
/// handed in by the browser that shows them, so that they behave exactly as
/// the tiles of the Library do: a click selects, a click with Ctrl or
/// Command held selects several, and a double click previews; on a phone or
/// tablet a tap previews, or selects while **Select several** is on.
///
/// Each callback is given the row the tile is in as well, which is what a
/// shift click selects across and what the preview steps through. A photo
/// in several rows, such as one with two people in it, is selected in all
/// of them at once.

class TileSelection {
  const TileSelection({
    required this.isSelected,
    required this.isFavourite,
    required this.isSharedOut,
    required this.showTicks,
    required this.onTap,
    required this.onActivate,
    required this.onToggleFavourite,
    required this.onInfo,
    this.selected = const [],
  });

  /// The photos selected, in the order they are shown, for what acts on the
  /// selection as a whole, such as deleting what was found in them.

  final List<MediaItem> selected;

  /// Whether a photo is part of the current selection.

  final bool Function(MediaItem item) isSelected;

  /// Whether a photo carries a heart.

  final bool Function(MediaItem item) isFavourite;

  /// Whether one of the user's own photos is shared with someone else.

  final bool Function(MediaItem item) isSharedOut;

  /// Whether the selected tiles are ticked as well as outlined.

  final bool showTicks;

  /// Called on a click or a tap on [item], in [row].

  final void Function(MediaItem item, List<MediaItem> row) onTap;

  /// Called on a double click on [item], in [row], which previews it.

  final void Function(MediaItem item, List<MediaItem> row) onActivate;

  /// Called when the heart on a tile is tapped.

  final void Function(MediaItem item) onToggleFavourite;

  /// Called when the info button on a tile is tapped.

  final void Function(MediaItem item) onInfo;
}

/// One row of [items] as tiles that scrolls sideways, as an album's does,
/// each tile selected and opened as [selection] says.

class TileRow extends StatelessWidget {
  const TileRow({
    super.key,
    required this.items,
    required this.tileExtent,
    required this.selection,
  });

  final List<MediaItem> items;

  /// The size of a tile, from the user's View preferences.

  final double tileExtent;

  final TileSelection selection;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: tileExtent,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: items.length,
      separatorBuilder: (context, index) => const Gap(4),
      itemBuilder: (context, index) {
        final item = items[index];
        final selected = selection.isSelected(item);
        return SizedBox.square(
          dimension: tileExtent,
          child: MediaTile(
            item: item,
            selected: selected,
            showCheck: selection.showTicks && selected,
            favourite: selection.isFavourite(item),
            sharedOut: selection.isSharedOut(item),
            onTap: () => selection.onTap(item, items),
            onActivate: () => selection.onActivate(item, items),
            onToggleFavourite: () => selection.onToggleFavourite(item),
            onInfo: () => selection.onInfo(item),
          ),
        );
      },
    ),
  );
}

/// A heading, with a person's portrait or an icon, the photo count and what
/// can be done, above a row of the photos ([TileRow]). The tiles select and
/// preview as the Library's do; the preview steps through the group's
/// photos, and Get Info is where the people in a photo are named.

class PersonSection extends StatelessWidget {
  const PersonSection({
    super.key,
    required this.title,
    required this.items,
    required this.tileExtent,
    this.person,
    this.unnamed = false,
    this.icon,
    this.onRename,
    this.action,
    required this.selection,
  });

  /// The person's name, or what the group is.

  final String title;

  final List<MediaItem> items;

  /// The size of a tile, from the user's View preferences.

  final double tileExtent;

  /// The person pictured beside the title, or null for a group that is not
  /// one person, which shows [icon].

  final PersonEntry? person;
  final IconData? icon;

  /// Whether [person] has no name yet, which shows their title muted.

  final bool unnamed;

  /// Called to give the person another name, or null when there is no one
  /// to name.

  final VoidCallback? onRename;

  /// Shown at the end of the heading, such as a button acting on the group.

  final Widget? action;

  /// How the tiles are selected and opened.

  final TileSelection selection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = items.length;
    final person = this.person;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (person != null)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRename,
                  child: FaceAvatar(
                    face: person.portrait,
                    item: person.portraitItem,
                  ),
                )
              else
                SizedBox.square(
                  dimension: 56,
                  child: Icon(icon, size: 32, color: theme.colorScheme.outline),
                ),
              const Gap(12),
              Flexible(
                child: InkWell(
                  onTap: onRename,
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: person == null || unnamed
                          ? theme.colorScheme.outline
                          : null,
                    ),
                  ),
                ),
              ),
              const Gap(8),
              Text(
                '$count ${count == 1 ? 'photo' : 'photos'}',
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              if (onRename != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: unnamed ? 'Name this person' : 'Rename this person',
                  onPressed: onRename,
                ),
              ?action,
            ],
          ),
          const Gap(8),
          TileRow(items: items, tileExtent: tileExtent, selection: selection),
        ],
      ),
    );
  }
}
