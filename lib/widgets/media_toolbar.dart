/// The actions available on the current selection.
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

import 'package:photopod/constants/media.dart';
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

  /// Change the layout and page size.

  final VoidCallback onView;

  /// Preview the first selected file.

  final VoidCallback onPreview;

  /// Re-read the current folder from the Pod.

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
    required this.onRefresh,
    required this.onSort,
  });
}

/// The row of actions at the top right of the main content area.
///
/// Everything that acts on a selection is greyed out until something is
/// selected, so the toolbar itself shows what is and is not currently
/// possible. It wraps onto a second line on a narrow window rather than
/// overflowing.

class MediaToolbar extends StatelessWidget {
  const MediaToolbar({
    super.key,
    required this.kind,
    required this.selectionCount,
    required this.canPreview,
    required this.sortOption,
    required this.actions,
  });

  /// Whether this is the Photos or the Videos section.

  final MediaKind kind;

  /// How many items are currently selected.

  final int selectionCount;

  /// Whether the first selected item is a file that can be previewed.

  final bool canPreview;

  /// The order currently in force, ticked in the Sort menu.

  final MediaSortOption sortOption;

  /// The callbacks the buttons invoke.

  final MediaActions actions;

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectionCount > 0;
    final many = selectionCount > 1;

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _AddButton(kind: kind, actions: actions),
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
        _button(
          icon: Icons.content_copy,
          label: 'Copy',
          enabled: hasSelection,
          onPressed: actions.onCopy,
          tooltip: '''

          **Copy**

          Put a second copy of the selected items into another folder. You
          will be asked where, and the destination is checked before anything
          is copied.

          ''',
        ),
        _button(
          icon: Icons.drive_file_move_outline,
          label: 'Move',
          enabled: hasSelection,
          onPressed: actions.onMove,
          tooltip: '''

          **Move**

          Move the selected items into another folder. You will be asked
          where, and the destination is checked before anything is moved.

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

          Give a new name to the selected item.
          ${many ? 'With several selected, the first one is renamed.' : ''}

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
          icon: Icons.visibility_outlined,
          label: 'Preview',
          enabled: canPreview,
          onPressed: actions.onPreview,
          tooltip:
              '''

          **Preview**

          Open the selected ${kind.noun} full size. Double tapping it does the
          same thing.
          ${many ? 'With several selected, the first one is shown.' : ''}

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

          Switch between thumbnails and the detailed list, and choose how many
          items appear on a page.

          ''',
        ),
        _button(
          icon: Icons.refresh,
          label: 'Refresh',
          enabled: true,
          onPressed: actions.onRefresh,
          tooltip: '''

          **Refresh**

          Read this folder from your Pod again.

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

class _AddButton extends StatelessWidget {
  const _AddButton({required this.kind, required this.actions});

  final MediaKind kind;
  final MediaActions actions;

  @override
  Widget build(BuildContext context) => MarkdownTooltip(
    message:
        '''

        **Add**

        Put ${kind.label.toLowerCase()} from this device into the folder you
        are looking at, or create a new folder to organise them.

        ''',
    child: PopupMenuButton<int>(
      icon: const Icon(Icons.add),
      onSelected: (value) =>
          value == 0 ? actions.onAddFiles() : actions.onNewFolder(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 0,
          child: ListTile(
            dense: true,
            leading: Icon(kind.icon),
            title: Text('Add ${kind.label.toLowerCase()}...'),
          ),
        ),
        const PopupMenuItem(
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
