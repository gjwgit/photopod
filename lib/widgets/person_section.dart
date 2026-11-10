/// One person in the People section, with every photo they are in.
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
import 'package:photopod/services/people.dart';
import 'package:photopod/widgets/face_avatar.dart';
import 'package:photopod/widgets/media_thumbnail.dart';

/// What a person is listed as before they have been named.

const String unnamedPerson = 'Add a name';

/// A person's portrait, name and photo count, above a row of their photos
/// that scrolls sideways, as an album's does. A tap on a photo previews it,
/// and the preview steps through this person's photos.

class PersonSection extends StatelessWidget {
  const PersonSection({
    super.key,
    required this.person,
    required this.tileExtent,
    required this.onRename,
    required this.onMerge,
  });

  final PersonEntry person;

  /// The size of a tile, from the user's View preferences.

  final double tileExtent;

  final VoidCallback onRename;

  /// Called to say this person is the same as someone else, or null when
  /// there is no one else.

  final VoidCallback? onMerge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = person.items.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                customBorder: const CircleBorder(),
                onTap: onRename,
                child: FaceAvatar(
                  face: person.portrait,
                  item: person.portraitItem,
                ),
              ),
              const Gap(12),
              Flexible(
                child: InkWell(
                  onTap: onRename,
                  child: Text(
                    person.name ?? unnamedPerson,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: person.name == null
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
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Name this person',
                onPressed: onRename,
              ),
              IconButton(
                icon: const Icon(Icons.merge_type),
                tooltip: 'Same person as...',
                onPressed: onMerge,
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
                final item = person.items[index];
                return SizedBox.square(
                  dimension: tileExtent,
                  child: Material(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () =>
                          showPreviewDialog(context, item, items: person.items),
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
