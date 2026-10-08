/// The individual icons and menus the toolbar is built from.
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

part of 'media_toolbar.dart';

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
    required this.tooltip,
    required this.children,
  });

  final IconData icon;
  final String label;
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
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    ),
  );
}

class _FavouriteButton extends StatelessWidget {
  const _FavouriteButton({
    required this.favourite,
    required this.many,
    required this.onPressed,
  });

  final bool favourite;
  final bool many;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = favourite ? 'Remove from Favourites' : 'Add to Favourites';

    return MediaToolbar._button(
      icon: favourite ? Icons.favorite : Icons.favorite_border,
      label: label,
      onPressed: onPressed,
      colour: favourite ? const Color(0xFFE53935) : null,
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
    required this.many,
    required this.albumNames,
    required this.onAdd,
    required this.onCreate,
  });

  final bool many;
  final List<String> albumNames;
  final ValueChanged<String> onAdd;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => _ToolbarMenu(
    icon: Icons.drive_file_move_outline,
    label: 'Add to album',
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

/// The overflow menu at the end of the row, holding the actions reached for
/// less often. Like the row, it lists only what can be done right now.

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => _ToolbarMenu(
    icon: Icons.more_vert,
    label: 'More',
    tooltip: '''

    **More**

    The actions used less often, such as duplicating, renaming or describing
    the selected items, and reading everything from your Pod again.

    ''',
    children: children,
  );
}
