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
/// Everything that acts on a selection is greyed out until something is
/// selected, so the toolbar itself shows what is and is not currently
/// possible. It wraps onto a second line on a narrow window rather than
/// overflowing. Which buttons appear at all depends on the section: only the
/// Library browses folders, so only the Library offers to add files to one,
/// and only the Albums section offers to take files out of an album.

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

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectionCount > 0;
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
            enabled: true,
            onPressed: actions.onAddFiles,
            tooltip: '''

          **Add photos and videos**

          Choose photos and videos on this device and put them into the folder
          you are looking at. They are encrypted with your security key on
          the way into your Pod.

          ''',
          ),
        _FavouriteButton(
          enabled: hasFiles,
          favourite: allFavourite,
          many: manyFiles,
          onPressed: actions.onToggleFavourite,
        ),
        _AddToAlbumButton(
          enabled: hasFiles,
          many: manyFiles,
          albumNames: albumNames,
          onAdd: actions.onAddToAlbum,
          onCreate: actions.onCreateAlbum,
        ),
        _button(
          icon: Icons.content_copy,
          label: 'Duplicate',
          enabled: hasFiles,
          onPressed: actions.onDuplicate,
          tooltip: '''

          **Duplicate**

          Make a copy of each selected photo and video beside the original,
          called `name_copy`, or `name_copy_1`, `name_copy_2` and so on when
          that is taken. A copy starts with no heart and in no album.

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
          icon: Icons.drive_file_rename_outline,
          label: 'Rename',
          enabled: hasSelection,
          onPressed: actions.onRename,
          tooltip:
              '''

          **Rename**

          Give the selected item a new name. It keeps its heart and its place
          in every album.
          ${many ? 'With several selected, the first one is renamed.' : ''}

          ''',
        ),
        _button(
          icon: Icons.delete_outline,
          label: 'Delete',
          enabled: hasSelection,
          onPressed: actions.onDelete,
          tooltip: '''

          **Delete**

          Remove the selected items from your Pod, and from every album they
          are in. Folders are removed with everything inside them, and nothing
          can be undone.

          ''',
        ),
        if (section == LibrarySection.albums)
          _button(
            icon: Icons.remove_circle_outline,
            label: 'Remove from album',
            enabled: canRemoveFromAlbum,
            onPressed: actions.onRemoveFromAlbum,
            tooltip: '''

          **Remove from album**

          Take the selected items out of the album they were selected in. The
          photos and videos themselves stay in your Pod, and in any other
          album they belong to.

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

          Read the album, your hearts and your albums from your Pod again.

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
    Color? colour,
  }) => MarkdownTooltip(
    message: tooltip,
    child: _ToolbarIcon(
      icon: icon,
      label: label,
      onPressed: enabled ? onPressed : null,
      colour: colour,
    ),
  );
}

/// The size every icon in the toolbar is drawn at.

const double toolbarIconSize = 24;

/// One icon in the toolbar.
///
/// Every button, the two menus included, is drawn by this one widget, so they
/// are all exactly the same size. The plain [IconButton.tooltip] is left
/// unset so that it does not compete with the Markdown tooltip, and the name
/// is carried to screen readers by [Semantics] instead.

class _ToolbarIcon extends StatelessWidget {
  const _ToolbarIcon({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.colour,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? colour;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: IconButton(
      iconSize: toolbarIconSize,
      icon: Icon(icon, color: colour),
      onPressed: onPressed,
    ),
  );
}

/// A toolbar icon that opens a menu.
///
/// Built on [MenuAnchor] rather than [PopupMenuButton], which brings its own
/// "Show menu" tooltip to compete with the Markdown one and draws its icon
/// with padding of its own.

class _ToolbarMenu extends StatelessWidget {
  const _ToolbarMenu({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.tooltip,
    required this.children,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final String tooltip;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: children,
    builder: (context, controller, child) => MarkdownTooltip(
      message: tooltip,
      child: _ToolbarIcon(
        icon: icon,
        label: label,
        onPressed: enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
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

    return MediaToolbar._button(
      icon: favourite ? Icons.favorite : Icons.favorite_border,
      label: label,
      enabled: enabled,
      onPressed: onPressed,
      colour: enabled && favourite ? const Color(0xFFE53935) : null,
      tooltip:
          '''

      **$label**

      ${favourite ? 'Take the heart away from' : 'Put a heart on'} the
      selected ${many ? 'items' : 'item'}, so ${many ? 'they' : 'it'}
      ${favourite ? 'no longer appears' : 'appears'} in Favourites. Hearts
      are kept in your Pod, so they follow you from one device to the next.

      ''',
    );
  }
}

/// Put the selected files into an album: Favourites, any of the user's own
/// albums, or a new one made on the spot.

class _AddToAlbumButton extends StatelessWidget {
  const _AddToAlbumButton({
    required this.enabled,
    required this.many,
    required this.albumNames,
    required this.onAdd,
    required this.onCreate,
  });

  final bool enabled;
  final bool many;
  final List<String> albumNames;
  final ValueChanged<String> onAdd;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => _ToolbarMenu(
    icon: Icons.drive_file_move_outline,
    label: 'Add to album',
    enabled: enabled,
    tooltip:
        '''

        **Add to album**

        Put the selected ${many ? 'items' : 'item'} into Favourites or into
        one of your albums. **Create new album...** at the bottom of the menu
        makes a new album, names it, and puts the selection straight into
        it. The photos and videos stay where they are in your Pod; an album
        only gathers them together.

        ''',
    children: [
      MenuItemButton(
        leadingIcon: const Icon(Icons.favorite_outline),
        onPressed: () => onAdd(favouritesAlbumName),
        child: const Text(favouritesAlbumName),
      ),
      for (final name in albumNames)
        MenuItemButton(
          leadingIcon: const Icon(Icons.photo_album_outlined),
          onPressed: () => onAdd(name),
          child: Text(name),
        ),
      const Divider(height: 1),
      MenuItemButton(
        leadingIcon: const Icon(Icons.create_new_folder_outlined),
        onPressed: onCreate,
        child: const Text('Create new album...'),
      ),
    ],
  );
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sortOption, required this.onSort});

  final MediaSortOption sortOption;
  final ValueChanged<MediaSortOption> onSort;

  @override
  Widget build(BuildContext context) => _ToolbarMenu(
    icon: Icons.sort,
    label: 'Sort',
    enabled: true,
    tooltip:
        '''

        **Sort**

        Order folders and files by name or by the time they were last
        recorded as changing on the Pod. Folders always come first. Now:
        ${sortOption.displayLabel}.

        ''',
    children: [
      for (final option in MediaSortOption.values)
        MenuItemButton(
          // A tick marks the order in force; the others keep the same indent.
          leadingIcon: Icon(
            Icons.check,
            color: option == sortOption ? null : Colors.transparent,
          ),
          onPressed: () => onSort(option),
          child: Text(option.displayLabel),
        ),
    ],
  );
}
