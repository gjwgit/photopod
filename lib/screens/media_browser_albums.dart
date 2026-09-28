/// Gathering photos and videos into albums, and looking after the albums.
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

/// Everything to do with albums: putting the selection into one, making,
/// renaming and deleting them, and laying them out in the Albums section.
///
/// Favourites is treated throughout as one more album, the only one that
/// cannot be renamed or deleted.

extension MediaBrowserAlbums on MediaBrowserState {
  /// Every album as the Albums section lists it: Favourites first, then the
  /// user's own albums in alphabetical order. Each holds only what is still in
  /// the Pod, sorted as the user has chosen.

  List<AlbumEntry> _albumEntries(BuildContext context) {
    final option = context.read<ViewPrefs>().sortOption;
    final favourites = context.read<Favourites>();
    final albums = context.read<Albums>();
    final all = context.read<MediaIndex>().items;

    List<MediaItem> resolve(Set<String> paths) {
      final items = all.where((item) => paths.contains(item.path)).toList();
      MediaBrowserState._sortInPlace(items, option);
      return items;
    }

    return [
      AlbumEntry(
        name: favouritesAlbumName,
        items: resolve(favourites.paths),
        isSystem: true,
      ),
      for (final name in albums.names)
        AlbumEntry(name: name, items: resolve(albums.pathsOf(name))),
    ];
  }

  /// Handle a tap on [item] in the album called [album].
  ///
  /// The selection belongs to one album at a time, so a tap in a different
  /// album starts a new selection there rather than adding to the old one.

  void _handleAlbumTap(String album, MediaItem item, List<MediaItem> visible) {
    if (_selectedAlbum != album) {
      updateState(() {
        _selected.clear();
        _anchor = 0;
        _selectedAlbum = album;
      });
    }
    _handleTap(item, visible);
  }

  /// Put [items] into the album called [album], which may be Favourites.

  Future<void> _addToAlbum(
    BuildContext context,
    String album,
    List<MediaItem> items,
  ) async {
    if (items.isEmpty) return;

    if (album == favouritesAlbumName) {
      final favourites = context.read<Favourites>();

      // The heart button toggles, but Add to album only ever adds, so only
      // the items without a heart are handed over.

      final missing = items.where((item) => !favourites.contains(item));
      if (missing.isEmpty) return;
      if (await favourites.toggleAll(missing) || !context.mounted) return;
      await _albumSaveFailed(context, favourites.error);
      return;
    }

    final albums = context.read<Albums>();
    if (await albums.add(album, items) || !context.mounted) return;
    await _albumSaveFailed(context, albums.error);
  }

  /// Ask for a name, make the album, and put [items] into it.

  Future<void> _createAlbum(BuildContext context, List<MediaItem> items) async {
    final albums = context.read<Albums>();
    final name = await showAlbumNameDialog(
      context,
      existing: albums.names,
      selectedCount: items.length,
    );
    if (name == null || !context.mounted) return;

    if (!await albums.create(name)) {
      if (context.mounted) await _albumSaveFailed(context, albums.error);
      return;
    }
    if (items.isEmpty || !context.mounted) return;
    await _addToAlbum(context, name, items);
  }

  /// Take the selected files out of the album they were selected in.

  Future<void> _removeFromAlbum(BuildContext context) async {
    final album = _selectedAlbum;
    final items = _selectedFiles;
    if (album == null || items.isEmpty) return;

    final bool saved;
    final String? error;
    if (album == favouritesAlbumName) {
      final favourites = context.read<Favourites>();
      saved = await favourites.forget(items.map((item) => item.path));
      error = favourites.error;
    } else {
      final albums = context.read<Albums>();
      saved = await albums.remove(album, items);
      error = albums.error;
    }

    if (!context.mounted) return;
    if (saved) {
      updateState(_selected.clear);
      return;
    }
    await _albumSaveFailed(context, error);
  }

  /// Give the album called [album] a new name.

  Future<void> _renameAlbum(BuildContext context, String album) async {
    final albums = context.read<Albums>();
    final name = await showAlbumNameDialog(
      context,
      existing: albums.names,
      current: album,
    );
    if (name == null || !context.mounted) return;

    final renamed = await showWorking(
      context,
      'Renaming...',
      () => albums.rename(album, name),
    );
    if (!context.mounted) return;
    if (!renamed) {
      await _albumSaveFailed(context, albums.error);
      return;
    }
    if (_selectedAlbum == album) updateState(() => _selectedAlbum = name);
  }

  /// Delete the album called [album], after checking that is really wanted.

  Future<void> _deleteAlbum(BuildContext context, String album) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this album?',
      message:
          '"$album" will be deleted. The photos and videos in it stay in '
          'your Pod and in any other album they belong to.',
    );
    if (!confirmed || !context.mounted) return;

    final albums = context.read<Albums>();
    final deleted = await showWorking(
      context,
      'Deleting...',
      () => albums.delete(album),
    );
    if (!context.mounted) return;
    if (!deleted) {
      await _albumSaveFailed(context, albums.error);
      return;
    }
    if (_selectedAlbum == album) {
      updateState(() {
        _selected.clear();
        _selectedAlbum = null;
      });
    }
  }

  Future<void> _albumSaveFailed(BuildContext context, String? error) =>
      showErrorDialog(
        context,
        'Could not save your albums',
        'Albums are kept as files in your Pod, and the file could not be '
            'written.\n\n${error ?? ''}',
      );
}
