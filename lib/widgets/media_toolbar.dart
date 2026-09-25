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

import 'package:photopod/models/library_section.dart';
import 'package:photopod/models/view_prefs.dart';

/// What the toolbar can do, gathered in one place so the browser passes a
/// single object rather than a dozen callbacks.

class MediaActions {
  /// Add files from this device to the current folder.

  final VoidCallback onAddFiles;

  /// Create a new folder inside the current folder.

  final VoidCallback onNewFolder;

  /// Remove the selected items from the Pod.

  final VoidCallback onDelete;

  /// Copy the selected items elsewhere.

  final VoidCallback onCopy;

  /// Move the selected items elsewhere.

  final VoidCallback onMove;

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

  /// Add a heart to the selected files, or take it away.

  final VoidCallback onToggleFavourite;

  /// Re-read the album from the Pod.

  final VoidCallback onRefresh;

  /// Change the order items are shown in.

  final ValueChanged<MediaSortOption> onSort;

  const MediaActions({
    required this.onAddFiles,
    required this.onNewFolder,
    required this.onDelete,
    required this.onCopy,
    required this.onMove,
    required this.onRename,
    required this.onShare,
    required this.onView,
    required this.onPreview,
    required this.onGetInfo,
    required this.onToggleFavourite,
    required this.onRefresh,
    required this.onSort,
  });
}

/// The row of actions at the top right of the main content area.
///
/// Everything that acts on a selection is greyed out until something is
/// selected, so the toolbar itself shows what is and is not currently
/// possible. It wraps onto a second line on a narrow window rather than
/// overflowing. Which buttons appear at all depends on the section: only the
/// Library browses folders, so only the Library offers to add to one, or to
/// copy, move and rename what is in it.

class MediaToolbar extends StatelessWidget {
  const MediaToolbar({
    super.key,
    required this.section,
    required this.selectionCount,
    required this.fileCount,
    required this.allFavourite,
    required this.sortOption,
    required this.actions,
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

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectionCount > 0;
    final hasFiles = fileCount > 0;
    final many = selectionCount > 1;
    final browsing = section.browsesFolders;

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (browsing) _AddButton(actions: actions),
        _FavouriteButton(
          enabled: hasFiles,
          favourite: allFavourite,
          many: fileCount > 1,
          onPressed: actions.onToggleFavourite,
        ),
        _button(
          icon: Icons.info_outline,
          label: 'Get Info',
          enabled: hasFiles,
          onPressed: actions.onGetInfo,
          tooltip:
              '''

          **Get Info**

          Show everything known about the selected item: its size, when it was
          added, how big the picture is, which camera took it and where.
          ${many ? 'With several selected, the first one is described.' : ''}

          ''',
        ),
        _button(
          icon: Icons.visibility_outlined,
          label: 'Preview',
          enabled: hasFiles,
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
          icon: Icons.share_outlined,
          label: 'Share',
          enabled: hasSelection,
          onPressed: actions.onShare,
          tooltip: '''

          **Share**

          Give other Solid users access to the selected items, by WebID and
          with the permissions you choose.

          ''',
        ),
        _button(
          icon: Icons.delete_outline,
          label: 'Delete',
          enabled: hasSelection,
          onPressed: actions.onDelete,
          tooltip: '''

          **Delete**

          Remove the selected items from your Pod. Folders are removed with
          everything inside them, and nothing can be undone.

          ''',
        ),
        if (browsing) _OrganiseButton(enabled: hasSelection, actions: actions),
        _SortButton(sortOption: sortOption, onSort: actions.onSort),
        _button(
          icon: Icons.tune,
          label: 'View',
          enabled: true,
          onPressed: actions.onView,
          tooltip: '''

          **View**

          Switch between the tiles and the detailed list, choose how big the
          tiles are, and choose how many items appear on a page.

          ''',
        ),
        _button(
          icon: Icons.refresh,
          label: 'Refresh',
          enabled: true,
          onPressed: actions.onRefresh,
          tooltip: '''

          **Refresh**

          Read the album from your Pod again.

          ''',
        ),
      ],
    );
  }

  static Widget _button({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
    required String tooltip,
  }) => MarkdownTooltip(
    message: tooltip,
    // The plain [IconButton.tooltip] is left unset so that it does not
    // compete with the Markdown tooltip, and the name is carried to
    // screen readers by [Semantics] instead.

    child: Semantics(
      label: label,
      button: true,
      child: IconButton(
        icon: Icon(icon),
        onPressed: enabled ? onPressed : null,
      ),
    ),
  );
}

class _FavouriteButton extends StatelessWidget {
  const _FavouriteButton({
    required this.enabled,
    required this.favourite,
    required this.many,
    required this.onPressed,
  });

  final bool enabled;
  final bool favourite;
  final bool many;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = favourite ? 'Remove from Favourites' : 'Add to Favourites';

    return MarkdownTooltip(
      message:
          '''

      **$label**

      ${favourite ? 'Take the heart away from' : 'Put a heart on'} the
      selected ${many ? 'items' : 'item'}, so ${many ? 'they' : 'it'}
      ${favourite ? 'no longer appears' : 'appears'} in the Favourites
      section. Hearts are kept in your Pod, so they follow you from one
      device to the next.

      ''',
      child: Semantics(
        label: label,
        button: true,
        child: IconButton(
          icon: Icon(
            favourite ? Icons.favorite : Icons.favorite_border,
            color: enabled && favourite ? const Color(0xFFE53935) : null,
          ),
          onPressed: enabled ? onPressed : null,
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.actions});

  final MediaActions actions;

  @override
  Widget build(BuildContext context) => MarkdownTooltip(
    message: '''

        **Add**

        Put photos and videos from this device into the folder you are
        looking at, or create a new folder to organise them.

        ''',
    child: PopupMenuButton<int>(
      icon: const Icon(Icons.add),
      onSelected: (value) =>
          value == 0 ? actions.onAddFiles() : actions.onNewFolder(),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 0,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.add_photo_alternate_outlined),
            title: Text('Add photos and videos...'),
          ),
        ),
        PopupMenuItem(
          value: 1,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.create_new_folder_outlined),
            title: Text('New folder...'),
          ),
        ),
      ],
    ),
  );
}

/// Copy, move and rename, which belong together and are reached for far less
/// often than the rest, so they sit behind one menu rather than taking three
/// more places in the row.

class _OrganiseButton extends StatelessWidget {
  const _OrganiseButton({required this.enabled, required this.actions});

  final bool enabled;
  final MediaActions actions;

  @override
  Widget build(BuildContext context) => MarkdownTooltip(
    message: '''

        **Organise**

        Copy or move the selected items into another folder, or give the
        first of them a new name. A destination folder that is not there yet
        can be created along the way.

        ''',
    child: PopupMenuButton<int>(
      icon: const Icon(Icons.more_horiz),
      enabled: enabled,
      onSelected: (value) => switch (value) {
        0 => actions.onCopy(),
        1 => actions.onMove(),
        _ => actions.onRename(),
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 0,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.content_copy),
            title: Text('Copy to...'),
          ),
        ),
        PopupMenuItem(
          value: 1,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.drive_file_move_outline),
            title: Text('Move to...'),
          ),
        ),
        PopupMenuItem(
          value: 2,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.drive_file_rename_outline),
            title: Text('Rename...'),
          ),
        ),
      ],
    ),
  );
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sortOption, required this.onSort});

  final MediaSortOption sortOption;
  final ValueChanged<MediaSortOption> onSort;

  @override
  Widget build(BuildContext context) => MarkdownTooltip(
    message: '''

        **Sort**

        Order folders and files by name or by the time they were last
        recorded as changing on the Pod. Folders always come first.

        ''',
    child: PopupMenuButton<MediaSortOption>(
      icon: const Icon(Icons.sort),
      initialValue: sortOption,
      onSelected: onSort,
      itemBuilder: (context) => [
        for (final option in MediaSortOption.values)
          PopupMenuItem(value: option, child: Text(option.displayLabel)),
      ],
    ),
  );
}
