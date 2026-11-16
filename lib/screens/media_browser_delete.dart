/// Deleting photos, videos and folders, and all that goes with them.
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

/// Deleting the selected items: from the Pod, and from the hearts, the
/// albums, the album index, People and Tags.

extension MediaBrowserDelete on MediaBrowserState {
  /// Remove the selected items, after checking that is really wanted.
  ///
  /// The flat sections show items from every folder at once, so the selection
  /// is grouped by the folder each item sits in and each group is deleted in
  /// its own batch.

  Future<void> _delete(BuildContext context) async {
    final items = _selectedItems;
    if (items.isEmpty) return;
    if (await _needsPod(context, 'delete photos and videos')) return;
    if (!context.mounted) return;

    // What someone else shared with the user is theirs, not the user's, so
    // it is declined rather than deleted. See [SharedWithMe.decline].

    final own = items.where((item) => !item.isShared).toList();
    final shared = items.where((item) => item.isShared).toList();

    final folders = own.where((item) => item.isFolder).length;
    final single = items.length == 1;
    final subject = single ? '"${items.first.name}"' : '${items.length} items';
    final nested = folders == 0
        ? ''
        : single
        ? ' Everything inside it goes too.'
        : ' Everything inside the $folders selected '
              '${folders == 1 ? 'folder' : 'folders'} goes too.';
    final String message;
    if (shared.isEmpty) {
      message =
          '$subject will be removed from your Pod.$nested '
          'This cannot be undone.';
    } else if (own.isEmpty) {
      message =
          '$subject ${single ? 'was' : 'were'} shared with you. '
          '${single ? 'It' : 'They'} will no longer be shared with you, and '
          'will be removed from your Library, your favourites and your '
          'albums. The owner keeps the original${single ? '' : 's'} and can '
          'share ${single ? 'it' : 'them'} with you again.';
    } else {
      message =
          '${own.length} of them will be removed from your Pod.$nested '
          'This cannot be undone.\n\n'
          '${shared.length == 1 ? 'One was' : '${shared.length} were'} '
          'shared with you by someone else, and will no longer be shared '
          'with you instead. The owner keeps the original.';
    }

    final confirmed = await showConfirmDialog(
      context,
      title: single ? 'Delete this item?' : 'Delete ${items.length} items?',
      message: message,
    );
    if (!confirmed || !context.mounted) return;

    final favourites = context.read<Favourites>();
    final albums = context.read<Albums>();
    final index = context.read<MediaIndex>();
    final sharedWithMe = context.read<SharedWithMe>();
    final analysed = [context.read<People>(), context.read<PhotoTags>()];

    final failed = await showWorking(context, 'Deleting...', () async {
      return {
        if (own.isNotEmpty) ...await _deleteByFolder(own),
        if (shared.isNotEmpty) ...await sharedWithMe.decline(shared),
      };
    });

    for (final item in items) {
      ThumbnailCache.instance.evict(item.url);
    }

    // Only what actually went is forgotten, so an item the server refused to
    // remove keeps its heart and its place in every album. A shared item's
    // path is its URL in its owner's Pod, which is what the hearts and the
    // albums hold for it.

    final gone = [
      for (final item in items)
        if (!failed.containsKey(item)) item.path,
    ];
    await favourites.forget(gone);
    await albums.forget(gone);

    // The faces and tags found in a deleted photo, or in any photo of a
    // deleted folder, are deleted from their files in the Pod along with it.

    final deleted = own.where((item) => !failed.containsKey(item)).toList();
    for (final section in analysed) {
      await section.forget(deleted);
    }

    // Deleting a file already took away everyone's access to it, so album
    // sharing only has to stop remembering it.

    if (context.mounted) {
      await context.read<AlbumSharing>().forget([
        for (final item in own)
          if (!failed.containsKey(item)) item.path,
      ]);
    }
    index.invalidate();
    await reload();

    if (context.mounted && failed.isNotEmpty) {
      await showErrorDialog(
        context,
        'Some items could not be deleted',
        failed.entries.map((e) => '${e.key.name}: ${e.value}').join('\n\n'),
      );
    }
  }

  // Delete [items] a folder at a time, reporting which of them would not go
  // along with what the server said about each.
  //
  // The batch delete answers with the names it was handed, which are the
  // names on the server — `3f9c…e1.jpg.enc.ttl` rather than `beach.jpg` — so
  // the failures are matched back to the items they belong to before anything
  // is decided from them.

  Future<Map<MediaItem, String>> _deleteByFolder(List<MediaItem> items) async {
    final byFolder = <String, List<MediaItem>>{};
    for (final item in items) {
      byFolder.putIfAbsent(item.parentPath, () => <MediaItem>[]).add(item);
    }

    final failed = <MediaItem, String>{};
    for (final entry in byFolder.entries) {
      try {
        final result = await PodMediaOps.deleteAll(entry.key, entry.value);
        for (final item in entry.value) {
          final reason = result.failed[item.rawName];
          if (reason != null) failed[item] = reason;
        }
      } on Object catch (e) {
        for (final item in entry.value) {
          failed[item] = '$e';
        }
      }
    }
    return failed;
  }
}
