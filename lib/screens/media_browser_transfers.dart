/// Duplicate and rename from the toolbar.
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

/// The toolbar actions that make a copy of an item or give it a new name.

extension MediaBrowserTransfers on MediaBrowserState {
  /// Make a copy of each selected photo and video beside the original.
  ///
  /// The copy is called `beach_copy.jpg`, or `beach_copy_1.jpg` and so on
  /// when that is taken. It is a new photo, so it starts with no heart and in
  /// no album. Any selected folder is left alone.

  Future<void> _duplicate(BuildContext context) async {
    final files = _selectedFiles;
    if (files.isEmpty) return;

    // The original has to be decrypted and the copy encrypted again.

    if (!await _ensureSecurityKey(context)) return;
    if (!context.mounted) return;

    final index = context.read<MediaIndex>();

    await _guard(
      context,
      files.length == 1
          ? 'Could not duplicate "${files.first.name}"'
          : 'Could not duplicate the items',
      () => showWorking(
        context,
        'Duplicating...',
        () => PodMediaOps.duplicateAll(files),
      ),
    );

    index.invalidate();
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

    // Solid has no rename, so the item is rewritten under its new name, which
    // means decrypting and re-encrypting it.

    if (!await _ensureSecurityKey(context)) return;
    if (!context.mounted) return;

    final favourites = context.read<Favourites>();
    final albums = context.read<Albums>();
    final index = context.read<MediaIndex>();
    final sharing = context.read<AlbumSharing>();
    String? renamed;

    await _guard(
      context,
      'Could not rename "${item.name}"',
      () => showWorking(
        context,
        'Renaming...',
        () async => renamed = await PodMediaOps.rename(item, name),
      ),
    );

    ThumbnailCache.instance.evict(item.url);
    if (renamed != null) {
      await favourites.retarget({item.path: renamed!});
      await albums.retarget({item.path: renamed!});

      // The renamed item is a new file, which has to be shared again with
      // everyone its albums are shared with.

      await sharing.forget([item.path]);
    }
    index.invalidate();
    await reload();
    if (renamed != null && context.mounted) await _syncSharing(context);
  }
}
