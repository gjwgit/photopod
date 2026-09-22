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

    // A single selected file can be given a new name by ending the
    // destination with one, so tell the dialogue which file that would be.

    final renameable = items.length == 1 && !items.first.isFolder
        ? items.first.name
        : null;

    final destination = await showDestinationDialog(
      context,
      rootPath: _root,
      startPath: _path,
      title: '$verb $subject',
      actionLabel: verb,
      renameableFile: renameable,
    );

    if (destination == null || !context.mounted) return;

    // Both halves of a copy touch encrypted resources: the source has to be
    // decrypted and the new copy encrypted again.

    if (!await _ensureSecurityKey(context)) return;
    if (!context.mounted) return;

    // Moving into the folder the items already sit in does nothing, unless a
    // new name came with it, which makes the move a rename.

    if (move && destination.folderPath == _path && !destination.renames) {
      await showErrorDialog(
        context,
        'Nothing to move',
        'The items are already in "${destination.folderPath}".',
      );
      return;
    }

    await _guard(
      context,
      'Could not ${verb.toLowerCase()} the items',
      () => showWorking(
        context,
        '${move ? 'Moving' : 'Copying'}...',
        () => _apply(items, destination, move: move),
      ),
    );

    if (move) {
      for (final item in items) {
        ThumbnailCache.instance.evict(item.url);
      }
    }
    await reload();
  }

  /// Carry out the copy or the move that [destination] describes.

  Future<void> _apply(
    List<MediaItem> items,
    Destination destination, {
    required bool move,
  }) {
    final newName = destination.newName;
    if (newName != null) {
      // The dialogue only accepts a name when exactly one file is selected.

      return move
          ? PodMediaOps.moveAs(items.first, destination.folderPath, newName)
          : PodMediaOps.copyAs(items.first, destination.folderPath, newName);
    }

    return move
        ? PodMediaOps.moveItems(items, destination.folderPath)
        : PodMediaOps.copyItems(items, destination.folderPath);
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

    // Solid has no rename, so the item is rewritten under its new name, which
    // means decrypting and re-encrypting it.

    if (!await _ensureSecurityKey(context)) return;
    if (!context.mounted) return;

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
