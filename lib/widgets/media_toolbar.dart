/// The row of actions above the album.
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

import 'package:photopod/models/albums.dart' show favouritesAlbumName;
import 'package:photopod/models/library_section.dart';
import 'package:photopod/models/view_prefs.dart';

part 'media_toolbar_buttons.dart';

/// What the toolbar can do, gathered in one place so the browser passes a
/// single object rather than a dozen callbacks.

class MediaActions {
  /// Add files from this device to the current folder.

  final VoidCallback onAddFiles;

  /// Remove the selected items from the Pod.

  final VoidCallback onDelete;

  /// Make a copy of each selected file beside the original.

  final VoidCallback onDuplicate;

  /// Rename the first selected item.

  final VoidCallback onRename;

  /// Grant others access to the selected items.

  final VoidCallback onShare;

  /// Change the layout, the tile size and the page size.

  final VoidCallback onView;

  /// Preview the first selected file.

  final VoidCallback onPreview;

  /// Show everything known about the first selected file.

  final VoidCallback onGetInfo;

  /// Save the originals of the selected files onto this device.

  final VoidCallback onDownload;

  /// Add a heart to the selected files, or take it away.

  final VoidCallback onToggleFavourite;

  /// Put the selected files into the named album, which may be Favourites.

  final ValueChanged<String> onAddToAlbum;

  /// Ask for a name and make a new album.

  final VoidCallback onCreateAlbum;

  /// Take the selected files out of the album they were selected in.

  final VoidCallback onRemoveFromAlbum;

  /// Re-read the album from the Pod.

  final VoidCallback onRefresh;

  /// Change the order items are shown in.

  final ValueChanged<MediaSortOption> onSort;

  const MediaActions({
    required this.onAddFiles,
    required this.onDelete,
    required this.onDuplicate,
    required this.onRename,
    required this.onShare,
    required this.onView,
    required this.onPreview,
    required this.onGetInfo,
    required this.onDownload,
    required this.onToggleFavourite,
    required this.onAddToAlbum,
    required this.onCreateAlbum,
    required this.onRemoveFromAlbum,
    required this.onRefresh,
    required this.onSort,
  });
}

/// The row of actions at the top right of the main content area.
///
/// Only what can be done right now is shown: an action that needs a
/// selection appears once something is selected, one that needs a file
/// appears once a file is among the selection, and one that changes the item
/// itself stays away while the selection includes something shared with the
/// user, which only its owner can change. The everyday actions sit in the
/// row; the occasional ones (Duplicate, Rename, Get Info and Refresh) wait in
/// the **More** menu at the end, keeping the row short. It wraps onto a second
/// line on a narrow window rather than overflowing. Which buttons appear at
/// all also depends on the section: only the Library browses folders, so only
/// the Library offers to add files to one, and only the Albums section offers
/// to make a new album on its own or to take files out of one.

class MediaToolbar extends StatelessWidget {
  const MediaToolbar({
    super.key,
    required this.section,
    required this.selectionCount,
    required this.fileCount,
    required this.allFavourite,
    required this.sortOption,
    required this.actions,
    this.albumNames = const [],
    this.canRemoveFromAlbum = false,
    this.hasShared = false,
  });

  /// Which section of the app this toolbar sits in.

  final LibrarySection section;

  /// How many items are currently selected, folders included.

  final int selectionCount;

  /// How many of the selected items are files rather than folders. A folder
  /// has nothing to preview, nothing to describe and no heart to give.

  final int fileCount;

  /// Whether every selected file already carries a heart, which decides
  /// whether the heart button offers to add one or to take it away.

  final bool allFavourite;

  /// The order currently in force, ticked in the Sort menu.

  final MediaSortOption sortOption;

  /// The callbacks the buttons invoke.

  final MediaActions actions;

  /// The user's own albums, listed in the Add to album menu beneath
  /// Favourites.

  final List<String> albumNames;

  /// Whether the selection sits in one album it can be taken out of, which
  /// only happens in the Albums section.

  final bool canRemoveFromAlbum;

  /// Whether the selection holds anything someone else shared with the user.
  /// Those files belong to their owner, so they cannot be renamed, deleted,
  /// duplicated or shared on from here.

  final bool hasShared;

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectionCount > 0;
    final canChange = hasSelection && !hasShared;
    final hasFiles = fileCount > 0;
    final many = selectionCount > 1;
    final manyFiles = fileCount > 1;

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (section.browsesFolders)
          _button(
            icon: Icons.add,
            label: 'Add photos and videos',
            onPressed: actions.onAddFiles,
            tooltip: '''

          **Add photos and videos**

          Choose photos and videos on this device and put them into the folder
          you are looking at. They are encrypted with your security key on
          the way into your Pod.

          ''',
          ),
        // The Albums section has no folder to add files to, so the place the
        // Library gives to adding photos goes to making a new album instead.

        if (section == LibrarySection.albums)
          _button(
            icon: Icons.create_new_folder_outlined,
            label: 'Create new album',
            onPressed: actions.onCreateAlbum,
            tooltip: '''

          **Create new album**

          Make a new album and give it a name. Any photos and videos selected
          at the time go straight into it; otherwise it starts empty, ready
          for **Add to album**.

          ''',
          ),
        if (hasFiles) ...[
          _FavouriteButton(
            favourite: allFavourite,
            many: manyFiles,
            onPressed: actions.onToggleFavourite,
          ),
          _AddToAlbumButton(
            many: manyFiles,
            albumNames: albumNames,
            onAdd: actions.onAddToAlbum,
            onCreate: actions.onCreateAlbum,
          ),
          _button(
            icon: Icons.visibility_outlined,
            label: 'Preview',
            onPressed: actions.onPreview,
            tooltip:
                '''

          **Preview**

          Open the selected photo or video full size. Double tapping its tile
          does the same thing.
          ${many ? 'With several selected, the first one is shown.' : ''}

          ''',
          ),
          _button(
            icon: Icons.download_outlined,
            label: 'Download',
            onPressed: actions.onDownload,
            tooltip:
                '''

          **Download**

          Save the original of each selected photo and video onto this
          device, at full size. The tiles and the preview show smaller copies
          kept beside it, which is what keeps browsing quick.
          ${manyFiles ? 'You are asked where to save each one in turn.' : ''}

          ''',
          ),
        ],
        if (canChange) ...[
          _button(
            icon: Icons.share_outlined,
            label: 'Share',
            onPressed: actions.onShare,
            tooltip: '''

          **Share**

          Give other Solid users access to the selected items, by WebID and
          with the permissions you choose. To share a whole album, use the
          share button on the album itself.

          ''',
          ),
          _button(
            icon: Icons.delete_outline,
            label: 'Delete',
            onPressed: actions.onDelete,
            tooltip: '''

          **Delete**

          Remove the selected items from your Pod, and from every album they
          are in. Folders are removed with everything inside them, and nothing
          can be undone.

          ''',
          ),
        ],
        if (section == LibrarySection.albums && canRemoveFromAlbum)
          _button(
            icon: Icons.remove_circle_outline,
            label: 'Remove from album',
            onPressed: actions.onRemoveFromAlbum,
            tooltip: '''

          **Remove from album**

          Take the selected items out of the album they were selected in. The
          photos and videos themselves stay in your Pod, and in any other
          album they belong to.

          ''',
          ),
        _SortButton(sortOption: sortOption, onSort: actions.onSort),
        _button(
          icon: Icons.tune,
          label: 'View',
          onPressed: actions.onView,
          tooltip: '''

          **View**

          Switch between the tiles and the detailed list, choose how big the
          tiles are, and choose how many items appear on a page.

          ''',
        ),
        _MoreButton(
          children: [
            if (hasFiles && !hasShared)
              _menuItem(
                icon: Icons.content_copy,
                label: 'Duplicate',
                onPressed: actions.onDuplicate,
                tooltip: '''

                **Duplicate**

                Make a copy of each selected photo and video beside the
                original, called `name_copy`, or `name_copy_1`, `name_copy_2`
                and so on when that is taken. A copy starts with no heart and
                in no album.

                ''',
              ),
            if (canChange)
              _menuItem(
                icon: Icons.drive_file_rename_outline,
                label: 'Rename',
                onPressed: actions.onRename,
                tooltip:
                    '''

                **Rename**

                Give the selected item a new name. It keeps its heart and its
                place in every album.
                ${many ? 'With several selected, the first one is renamed.' : ''}

                ''',
              ),
            if (hasFiles)
              _menuItem(
                icon: Icons.info_outline,
                label: 'Get Info',
                onPressed: actions.onGetInfo,
                tooltip:
                    '''

                **Get Info**

                Show everything known about the selected item: its size, when
                it was added, how big the picture is, which camera took it and
                where.
                ${many ? 'With several selected, the first one is described.' : ''}

                ''',
              ),
            if (hasFiles || canChange) const Divider(height: 1),
            _menuItem(
              icon: Icons.refresh,
              label: 'Refresh',
              onPressed: actions.onRefresh,
              tooltip: '''

              **Refresh**

              Read the album, your hearts and your albums from your Pod again.

              ''',
            ),
          ],
        ),
      ],
    );
  }

  static Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required String tooltip,
  }) => MarkdownTooltip(
    message: tooltip,
    child: MenuItemButton(
      leadingIcon: Icon(icon),
      onPressed: onPressed,
      child: Text(label),
    ),
  );

  static Widget _button({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required String tooltip,
    Color? colour,
  }) => MarkdownTooltip(
    message: tooltip,
    child: _ToolbarIcon(
      icon: icon,
      label: label,
      onPressed: onPressed,
      colour: colour,
    ),
  );
}
