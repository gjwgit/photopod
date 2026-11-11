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

import 'package:photopod/dialogs/preview_dialog.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/people.dart';
import 'package:photopod/widgets/face_avatar.dart';
import 'package:photopod/widgets/media_thumbnail.dart';

/// A heading, with a person's portrait or an icon, the photo count and what
/// can be done, above a row of the photos that scrolls sideways, as an
/// album's does. A tap on a photo previews it, and the preview steps through
/// the group's photos; Get Info there is where the people in it are named.

class PersonSection extends StatelessWidget {
  const PersonSection({
    super.key,
    required this.title,
    required this.items,
    required this.tileExtent,
    this.person,
    this.icon,
    this.onRename,
    this.action,
    this.onPreviewClosed,
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

  /// Called to give the person another name, or null when there is no one
  /// to name.

  final VoidCallback? onRename;

  /// Shown at the end of the heading, such as a button acting on the group.

  final Widget? action;

  /// Called once a preview opened from the row is closed, since what Get
  /// Info changed there may change the groups.

  final VoidCallback? onPreviewClosed;

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
                      color: person == null ? theme.colorScheme.outline : null,
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
                  tooltip: 'Rename this person',
                  onPressed: onRename,
                ),
              ?action,
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
                final item = items[index];
                return SizedBox.square(
                  dimension: tileExtent,
                  child: Material(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () async {
                        await showPreviewDialog(context, item, items: items);
                        onPreviewClosed?.call();
                      },
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
