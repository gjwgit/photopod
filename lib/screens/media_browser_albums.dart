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
/// Favourites is treated as one more album when adding to or removing from an
/// album, the only one that cannot be renamed or deleted. It is not listed in
/// the Albums section, though, as it has a section of its own.
///
/// Sharing an album shares the photos and videos in it, and every change to
/// what a shared album holds, or to who it is shared with, goes through
/// [_syncSharing] so that the photos keep up. Albums other people have shared
/// with the user are listed after the user's own, and are theirs to change,
/// not the user's.

extension MediaBrowserAlbums on MediaBrowserState {
  /// Every album as the Albums section lists it: the user's own albums in
  /// alphabetical order, then those shared with the user. Favourites is left
  /// out as it has its own section. Each holds only what is still in the Pod,
  /// sorted as the user has chosen.

  List<AlbumEntry> _albumEntries(BuildContext context) {
    final option = context.read<ViewPrefs>().sortOption;
    final albums = context.read<Albums>();
    final sharing = context.read<AlbumSharing>();
    final shared = context.read<SharedWithMe>();
    final all = context.read<MediaIndex>().items;

    List<MediaItem> resolve(Set<String> paths) {
      final items = all.where((item) => paths.contains(item.path)).toList();
      MediaBrowserState._sortInPlace(items, option);
      return items;
    }

    final titles = sharedAlbumTitles(shared.albums, albums.names);

    return [
      for (final name in albums.names)
        AlbumEntry(
          name: name,
          items: resolve(albums.pathsOf(name)),
          isSharedOut: sharing.isShared(name),
        ),
      for (final album in shared.albums)
        AlbumEntry(
          id: album.url,
          name: album.name,
          title: titles[album.url],
          items: resolve(album.itemUrls),
          sharedBy: album.ownerWebId,
        ),
    ];
  }

  /// Handle a tap on [item] in the album whose [AlbumEntry.id] is [album].
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
      final saved = await favourites.toggleAll(missing);
      if (!context.mounted) return;
      if (!saved) {
        await _albumSaveFailed(context, favourites.error);
        return;
      }
      await _syncSharing(context);
      return;
    }

    final albums = context.read<Albums>();
    final saved = await albums.add(album, items);
    if (!context.mounted) return;
    if (!saved) {
      await _albumSaveFailed(context, albums.error);
      return;
    }
    await _syncSharing(context);
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
    if (album == null || !_inOwnAlbum) return;
    await _removeItemsFromAlbum(context, album, _selectedFiles);
  }

  /// Take [items] out of the album called [album], which may be Favourites.
  ///
  /// Whatever is taken out is also dropped from the selection, so the toolbar
  /// never offers to act on an item that is no longer in view.

  Future<void> _removeItemsFromAlbum(
    BuildContext context,
    String album,
    List<MediaItem> items,
  ) async {
    if (items.isEmpty) return;

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
      if (_selectedAlbum == album) {
        updateState(() {
          for (final item in items) {
            _selected.remove(item.id);
          }
        });
      }
      await _syncSharing(context);
      return;
    }
    await _albumSaveFailed(context, error);
  }

  /// Share the album called [album], which holds [items], with other Solid
  /// users, through the same dialogue as sharing photos, and then bring the
  /// photos and videos in it into line with whatever the dialogue changed.

  Future<void> _shareAlbum(
    BuildContext context,
    String album,
    List<MediaItem> items,
  ) async {
    final String fileUrl;
    try {
      fileUrl = await _albumFileUrl(album);
    } on Object catch (e) {
      if (context.mounted) {
        await showErrorDialog(
          context,
          'Cannot share',
          'The album could not be found in your Pod.\n\n$e',
        );
      }
      return;
    }
    if (!context.mounted) return;

    // solidpod will not grant access to anything without the security key,
    // so it is asked for now rather than failing inside the dialogue.

    if (!await _ensureSecurityKey(context)) return;
    if (!context.mounted) return;

    // Only the user's own photos can be shared on, so anything in the album
    // that was itself shared with the user is not counted.

    await showAlbumShareDialog(
      context,
      albumName: album,
      albumFileUrl: fileUrl,
      itemCount: items.where((item) => !item.isShared).length,
    );
    if (!context.mounted) return;

    await context.read<AlbumSharing>().refresh(album, fileUrl);
    if (!context.mounted) return;
    await _syncSharing(context);
  }

  /// Share and unshare photos and videos until each is shared with exactly
  /// the people its albums are shared with.
  ///
  /// Nothing is asked of the Pod, and no security key is needed, when
  /// nothing has to change, which is the case for everyone who has never
  /// shared an album.

  Future<void> _syncSharing(BuildContext context) async {
    final sharing = context.read<AlbumSharing>();
    final favourites = context.read<Favourites>();
    final albums = context.read<Albums>();

    final List<SharingChange> changes;
    try {
      changes = await sharing.plan({
        favouritesAlbumName: favourites.paths,
        for (final name in albums.names) name: albums.pathsOf(name),
      });
    } on Object catch (e) {
      debugPrint('PhotoPod: could not plan album sharing: $e');
      return;
    }
    if (changes.isEmpty || !context.mounted) return;

    // Sharing an encrypted photo shares its key, so the key has to be in
    // hand first.

    if (!await _ensureSecurityKey(context)) return;
    if (!context.mounted) return;

    final failed = await showWorking(
      context,
      'Updating sharing...',
      () => sharing.apply(changes),
    );
    if (failed.isEmpty || !context.mounted) return;

    await showErrorDialog(
      context,
      'Some photos could not be shared or unshared',
      'The albums are as you left them, and PhotoPod will try these again '
          'the next time a shared album changes or you refresh the '
          'albums.\n\n${failed.join('\n\n')}',
    );
  }

  Future<String> _albumFileUrl(String album) => album == favouritesAlbumName
      ? Favourites.fileUrl()
      : Albums.fileUrlOf(album);

  /// Give the album called [album] a new name.

  Future<void> _renameAlbum(BuildContext context, String album) async {
    final albums = context.read<Albums>();
    final name = await showAlbumNameDialog(
      context,
      existing: albums.names,
      current: album,
    );
    if (name == null || !context.mounted) return;

    // The renamed album is a new file, with no access list of its own. So a
    // shared album is unshared under its old name, which tells its
    // recipients it has gone, and shared again with the same people under
    // the new one. Its photos stay shared throughout.

    final sharing = context.read<AlbumSharing>();
    await sharing.load();
    final recipients = sharing.recipientsOf(album);
    if (!context.mounted) return;
    if (recipients.isNotEmpty && !await _ensureSecurityKey(context)) return;
    if (!context.mounted) return;

    final failed = <String>[];
    final renamed = await showWorking(context, 'Renaming...', () async {
      if (recipients.isNotEmpty) {
        failed.addAll(
          await sharing.unshareAlbum(album, await Albums.fileUrlOf(album)),
        );
      }
      final ok = await albums.rename(album, name);
      if (recipients.isNotEmpty) {
        final target = ok ? name : album;
        failed.addAll(
          await sharing.shareAlbumFile(
            target,
            await Albums.fileUrlOf(target),
            recipients,
          ),
        );
      }
      return ok;
    });
    if (!context.mounted) return;
    if (!renamed) {
      await _albumSaveFailed(context, albums.error);
      return;
    }
    if (_selectedAlbum == album) updateState(() => _selectedAlbum = name);
    if (failed.isNotEmpty) await _sharingFailed(context, failed);
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
    final sharing = context.read<AlbumSharing>();
    final failed = <String>[];
    final deleted = await showWorking(context, 'Deleting...', () async {
      // Unshared first, while the file is still there to say so to its
      // recipients.

      if (sharing.isShared(album)) {
        failed.addAll(
          await sharing.unshareAlbum(album, await Albums.fileUrlOf(album)),
        );
      }
      return albums.delete(album);
    });
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
    if (failed.isNotEmpty) await _sharingFailed(context, failed);

    // The photos that were shared only through this album are unshared now.

    if (context.mounted) await _syncSharing(context);
  }

  Future<void> _sharingFailed(BuildContext context, List<String> failed) =>
      showErrorDialog(
        context,
        'Sharing could not be fully updated',
        failed.join('\n\n'),
      );

  Future<void> _albumSaveFailed(BuildContext context, String? error) =>
      showErrorDialog(
        context,
        'Could not save your albums',
        'Albums are kept as files in your Pod, and the file could not be '
            'written.\n\n${error ?? ''}',
      );
}
