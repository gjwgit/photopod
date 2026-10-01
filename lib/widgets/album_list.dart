/// The albums, each opening out into a row of its photos and videos.
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

import 'package:markdown_tooltip/markdown_tooltip.dart';

import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/shared_with_me.dart' show webIdLabel;
import 'package:photopod/widgets/media_grid.dart';

/// One album as the list shows it.

class AlbumEntry {
  /// What identifies the album in the list: its name for the user's own
  /// albums, and the URL of the album file for one shared with the user,
  /// which may well have the same name as one of the user's.

  final String id;

  /// The album's name, which is also the name of its file.

  final String name;

  /// What the album is listed as, when that differs from [name]: an album
  /// shared with the user that has the same name as another is told apart by
  /// who shared it.

  final String? title;

  /// What the album holds that is still in the Pod, in display order.

  final List<MediaItem> items;

  /// Whether this is Favourites, which cannot be renamed or deleted.

  final bool isSystem;

  /// The WebID of the person who shared the album with the user, or null for
  /// one of the user's own albums.

  final String? sharedBy;

  /// Whether the user has shared this album of their own with anyone.

  final bool isSharedOut;

  const AlbumEntry({
    String? id,
    required this.name,
    this.title,
    required this.items,
    this.isSystem = false,
    this.sharedBy,
    this.isSharedOut = false,
  }) : id = id ?? name;

  /// Whether someone else shared this album with the user, which makes it
  /// theirs to rename, delete or share, not the user's.

  bool get isFromOthers => sharedBy != null;

  /// What the album is listed as.

  String get displayName => title ?? name;
}

/// Every album as a collapsible row.
///
/// An opened album shows its photos and videos as one row of tiles that
/// scrolls sideways, so that a long album never pushes the next album off the
/// bottom of the window. The tiles behave exactly as they do in the Library:
/// a tap selects, a double tap previews, and the heart is there on hover.
/// Each tile in one of the user's own albums also has a button to take it out
/// of its album.

class AlbumList extends StatelessWidget {
  const AlbumList({
    super.key,
    required this.albums,
    required this.tileExtent,
    required this.isSelected,
    required this.isFavourite,
    required this.onTap,
    required this.onActivate,
    required this.onToggleFavourite,
    required this.onShare,
    required this.onRemoveFromAlbum,
    required this.onRename,
    required this.onDelete,
  });

  /// The albums to list, in the order they are shown.

  final List<AlbumEntry> albums;

  /// The size of a tile, from the user's View preferences.

  final double tileExtent;

  /// Whether [item], seen in the album whose [AlbumEntry.id] is [album], is
  /// selected.

  final bool Function(String album, MediaItem item) isSelected;

  /// Whether an item carries a heart.

  final bool Function(MediaItem item) isFavourite;

  /// Called on a single tap on [item] in the album whose [AlbumEntry.id] is
  /// [album].

  final void Function(String album, MediaItem item) onTap;

  /// Called on a double tap, which previews the file.

  final void Function(MediaItem item) onActivate;

  /// Called when the heart on a tile is tapped.

  final void Function(MediaItem item) onToggleFavourite;

  /// Called by the share button in an album's title bar, with the album's
  /// name. Only the user's own albums have one.

  final void Function(String album) onShare;

  /// Called by the remove button on [item] in the album called [album]. Only
  /// the user's own albums have one.

  final void Function(String album, MediaItem item) onRemoveFromAlbum;

  /// Called by the edit button in an album's title bar.

  final void Function(String album) onRename;

  /// Called by the delete button in an album's title bar.

  final void Function(String album) onDelete;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      for (final album in albums)
        _AlbumTile(
          // Keyed by name so that an album stays open, or closed, when one
          // above it is added, renamed or removed.
          key: ValueKey(album.id),
          album: album,
          list: this,
        ),
    ],
  );
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({super.key, required this.album, required this.list});

  final AlbumEntry album;
  final AlbumList list;

  @override
  Widget build(BuildContext context) {
    final n = album.items.length;
    final scheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      // The arrow goes to the front so that the title bar's own buttons can
      // sit at the end, where the arrow would otherwise be.
      controlAffinity: ListTileControlAffinity.leading,
      title: Row(
        children: [
          Icon(
            album.isSystem ? Icons.favorite : Icons.photo_album_outlined,
            size: 20,
            color: album.isSystem ? const Color(0xFFE53935) : scheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(album.displayName, overflow: TextOverflow.ellipsis),
          ),
          if (album.isFromOthers || album.isSharedOut) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: album.isFromOthers
                  ? 'Shared with you by ${webIdLabel(album.sharedBy!)}\n'
                        '${album.sharedBy}'
                  : 'You have shared this album',
              child: Semantics(
                label: album.isFromOthers
                    ? 'Shared with you by ${webIdLabel(album.sharedBy!)}'
                    : 'Shared album',
                child: Icon(Icons.people, size: 18, color: scheme.primary),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '$n item${n == 1 ? '' : 's'}'
        '${album.isSystem && !album.isFromOthers ? ' · system album' : ''}'
        '${album.isFromOthers ? ' · shared by ${webIdLabel(album.sharedBy!)}' : ''}'
        '${album.isSharedOut ? ' · shared' : ''}',
      ),
      trailing: album.isFromOthers ? null : _buildActions(),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        if (album.items.isEmpty)
          ListTile(
            dense: true,
            title: Text(
              album.isFromOthers
                  ? 'Nothing in this album has been shared with you yet.'
                  : album.isSystem
                  ? 'Nothing carries a heart yet. Tap the heart on any photo '
                        'or video to bring it here.'
                  : 'This album is empty. Select photos or videos anywhere '
                        'in PhotoPod and use Add to album to put them here.',
            ),
          )
        else
          SizedBox(
            height: list.tileExtent,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: album.items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final item = album.items[index];
                return SizedBox(
                  width: list.tileExtent,
                  child: MediaTile(
                    item: item,
                    selected: list.isSelected(album.id, item),
                    favourite: list.isFavourite(item),
                    onTap: () => list.onTap(album.id, item),
                    onActivate: () => list.onActivate(item),
                    onToggleFavourite: () => list.onToggleFavourite(item),
                    onRemoveFromAlbum: album.isFromOthers
                        ? null
                        : () => list.onRemoveFromAlbum(album.name, item),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // Favourites can be shared like any other album, but it is a system album,
  // so it has no rename or delete buttons.

  Widget _buildActions() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      MarkdownTooltip(
        message:
            '''

        **Share album**

        Let other Solid users, or a group of them, see "${album.name}" and
        the photos and videos in it.

        ''',
        child: Semantics(
          label: 'Share album',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => list.onShare(album.name),
          ),
        ),
      ),
      if (!album.isSystem) ...[
        MarkdownTooltip(
          message:
              '''

        **Rename album**

        Give "${album.name}" a new name. What is in it stays the same.

        ''',
          child: Semantics(
            label: 'Rename album',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => list.onRename(album.name),
            ),
          ),
        ),
        MarkdownTooltip(
          message:
              '''

        **Delete album**

        Remove "${album.name}". The photos and videos in it stay in your
        Pod; only the album goes.

        ''',
          child: Semantics(
            label: 'Delete album',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => list.onDelete(album.name),
            ),
          ),
        ),
      ],
    ],
  );
}
