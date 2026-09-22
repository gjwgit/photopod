/// Copy, move and rename from the toolbar.
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

part of 'media_browser.dart';

/// The toolbar actions that put items somewhere else or give them a new name.

extension MediaBrowserTransfers on MediaBrowserState {
  /// Copy or move the selected items to a folder the user chooses.
  ///
  /// The destination dialogue will not close on a path that is not there, so
  /// by the time this runs the folder has been confirmed to exist. Anything
  /// the Pod then refuses is reported and nothing is left half done: a move
  /// only deletes an item once its copy has been written.

  Future<void> _transfer(BuildContext context, {required bool move}) async {
    final items = _selectedItems;
    if (items.isEmpty) return;

    final verb = move ? 'Move' : 'Copy';
    final subject = items.length == 1
        ? '"${items.first.name}"'
        : '${items.length} items';

    final destination = await showDestinationDialog(
      context,
      rootPath: _root,
      startPath: _path,
      title: '$verb $subject',
      actionLabel: verb,
    );

    if (destination == null || !context.mounted) return;

    if (move && destination == _path) {
      await showErrorDialog(
        context,
        'Nothing to move',
        'The items are already in "$destination".',
      );
      return;
    }

    await _guard(
      context,
      'Could not ${verb.toLowerCase()} the items',
      () => showWorking(
        context,
        '${move ? 'Moving' : 'Copying'}...',
        () => move
            ? PodMediaOps.moveItems(items, destination)
            : PodMediaOps.copyItems(items, destination),
      ),
    );

    if (move) {
      for (final item in items) {
        ThumbnailCache.instance.evict(item.url);
      }
    }
    await reload();
  }

  /// Rename the first selected item.
  ///
  /// With several items selected only the first is renamed, since a single
  /// new name cannot sensibly be given to more than one thing. Solid has no
  /// rename operation, so the item is rewritten under its new name and the
  /// old one removed.

  Future<void> _rename(BuildContext context) async {
    final items = _selectedItems;
    if (items.isEmpty) return;

    final item = items.first;
    final name = await showRenameDialog(context, item);
    if (name == null || !context.mounted) return;

    await _guard(
      context,
      'Could not rename "${item.name}"',
      () => showWorking(
        context,
        'Renaming...',
        () => PodMediaOps.rename(item, name),
      ),
    );

    ThumbnailCache.instance.evict(item.url);
    await reload();
  }
}
