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
  /// new name cannot sensibly be given to more than one thing. A file or
  /// folder keeps the random name it is stored under, so renaming it changes
  /// only the name PhotoPod records for it, inside the file and in its table
  /// of names. One still stored under its own name is moved to a random name
  /// on the way, which changes its path, and everything that refers to it
  /// follows.

  Future<void> _rename(BuildContext context) async {
    final items = _selectedItems;
    if (items.isEmpty) return;

    final item = items.first;
    final name = await showRenameDialog(context, item);
    if (name == null || !context.mounted) return;

    // The names are kept encrypted, and rewriting a folder means decrypting
    // and re-encrypting everything in it, so either way the key is needed.

    if (!await _ensureSecurityKey(context)) return;
    if (!context.mounted) return;

    final favourites = context.read<Favourites>();
    final albums = context.read<Albums>();
    final index = context.read<MediaIndex>();
    final sharing = context.read<AlbumSharing>();
    var moves = const <String, String>{};

    await _guard(
      context,
      'Could not rename "${item.name}"',
      () => showWorking(
        context,
        'Renaming...',
        () async => moves = await PodMediaOps.rename(item, name),
      ),
    );

    if (moves.isNotEmpty) {
      ThumbnailCache.instance.evict(item.url);
      await favourites.retarget(moves);
      await albums.retarget(moves);

      // The moved files were shared again with everyone the old ones were
      // shared with, so album sharing only has to know where they went.

      await sharing.retarget(moves);
    }
    index.invalidate();
    await reload();
  }

  /// Move everything an earlier build stored under the name the user gave
  /// it to a random name; see [StorageUpgrade]. The album is held still
  /// behind a progress dialogue meanwhile, since an item moved while it is
  /// being changed could be lost.

  Future<void> _upgradeStorage(BuildContext context) async {
    if (!await StorageUpgrade.isNeeded() || !context.mounted) return;

    final favourites = context.read<Favourites>();
    final albums = context.read<Albums>();
    final sharing = context.read<AlbumSharing>();
    final index = context.read<MediaIndex>();

    final List<String> failed;
    try {
      failed = await showWorking(
        context,
        'Moving your photos, videos, folders and albums to random names on '
        'the server, so that their names stay private. This happens once, '
        'and may take a while...',
        () => StorageUpgrade.run(
          favourites: favourites,
          albums: albums,
          sharing: sharing,
        ),
        title: 'Updating your Pod',
        maxWidth: 420,
      );
    } on Object catch (e) {
      if (context.mounted) {
        await showErrorDialog(context, 'Could not update your Pod', '$e');
      }
      return;
    }

    index.invalidate();
    ThumbnailCache.instance.clear();
    if (!context.mounted) return;
    await reload(force: true);
    if (context.mounted) await _syncSharing(context);
    if (failed.isEmpty || !context.mounted) return;

    await showErrorDialog(
      context,
      'Some items still carry their own names',
      'They are as they were, and PhotoPod will try again the next time it '
          'starts.\n\n${failed.join('\n\n')}',
    );
  }
}
