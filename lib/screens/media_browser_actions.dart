/// Selecting items, and everything the toolbar does to them.
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

/// Selecting items, and everything the toolbar does to them.

extension MediaBrowserActions on MediaBrowserState {
  /// The callbacks handed to the toolbar.

  MediaActions _actions(BuildContext context) => MediaActions(
    onAddFiles: () => _addFiles(context),
    onNewFolder: () => _newFolder(context),
    onDelete: () => _delete(context),
    onCopy: () => _transfer(context, move: false),
    onMove: () => _transfer(context, move: true),
    onRename: () => _rename(context),
    onShare: () => showShareDialog(context, _selectedItems),
    onView: () => showViewOptionsDialog(context),
    onPreview: () => _previewFirst(context),
    onGetInfo: () => _getInfo(context),
    onToggleFavourite: () => _toggleFavourite(context, _selectedFiles),
    onRefresh: () => reload(force: true),
    onSort: (option) {
      context.read<ViewPrefs>().setSortOption(option);
      updateState(() => _page = 0);
    },
  );

  /// Handle a tap on [item], one of the items in [visible].
  ///
  /// A plain tap adds the item to the selection or takes it out again, which
  /// makes multiple selection work the same way with a mouse as with a
  /// finger. Holding shift selects everything between the last tap and this
  /// one. Tapping the background clears the selection.

  void _handleTap(MediaItem item, List<MediaItem> visible) {
    final index = visible.indexOf(item);
    final extend = HardwareKeyboard.instance.logicalKeysPressed.any(
      (key) =>
          key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight,
    );

    updateState(() {
      if (extend && index >= 0) {
        final anchor = _anchor.clamp(0, visible.length - 1);
        final from = anchor < index ? anchor : index;
        final to = anchor < index ? index : anchor;
        _selected.addAll(visible.sublist(from, to + 1).map((each) => each.id));
      } else {
        if (!_selected.add(item.id)) _selected.remove(item.id);
        if (index >= 0) _anchor = index;
      }
    });
  }

  /// Handle a double tap: open a folder, or preview a file.

  Future<void> _handleActivate(MediaItem item) async {
    if (item.isFolder) {
      await _goTo(item.path);
      return;
    }
    if (mounted) await showPreviewDialog(context, item);
  }

  /// Preview the first selected file, ignoring any selected folders.

  Future<void> _previewFirst(BuildContext context) async {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    await showPreviewDialog(context, files.first);
  }

  /// Describe the first selected file.
  ///
  /// The tiles carry no captions, so this is the one place the name, the
  /// size, the dates and the camera settings are all written out.

  Future<void> _getInfo(BuildContext context) async {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    await showInfoDialog(context, files.first, rootPath: _root);
  }

  /// Add a heart to [items], or take it away from all of them.

  Future<void> _toggleFavourite(
    BuildContext context,
    List<MediaItem> items,
  ) async {
    if (items.isEmpty) return;

    final favourites = context.read<Favourites>();
    if (await favourites.toggleAll(items) || !context.mounted) return;

    await showErrorDialog(
      context,
      'Could not save your favourites',
      'The hearts are kept in a file in your Pod, and that file could not be '
          'written.\n\n${favourites.error ?? ''}',
    );
  }

  /// Add files from this device to the folder being shown.
  ///
  /// The picker accepts photos and videos alike, since the Library shows both
  /// together, and a name that would not survive being put in a URL is tidied
  /// up rather than refused, so that a photo straight off a camera always
  /// lands.

  Future<void> _addFiles(BuildContext context) async {
    if (!await _folderIsWritable(context)) return;
    if (!context.mounted) return;

    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [...photoExtensions, ...videoExtensions],
        dialogTitle: 'Add photos and videos',
      );
    } on Object catch (e) {
      if (context.mounted) {
        await showErrorDialog(context, 'Could not open the file picker', '$e');
      }
      return;
    }

    if (picked.isEmpty || !context.mounted) return;

    // Everything is written encrypted, so the security key has to be in hand
    // before the first file goes up rather than part way through the batch.

    if (!await _ensureSecurityKey(context)) return;
    if (!context.mounted) return;

    final failed = <String, String>{};
    final renamed = <String, String>{};
    var added = 0;

    await showWorking(context, 'Adding to your Pod...', () async {
      for (final file in picked) {
        try {
          if (kindOf(file.name) == null) {
            failed[file.name] = 'not a photo or video PhotoPod supports';
            continue;
          }
          final name = await PodMediaOps.freeName(
            _path,
            safeResourceName(file.name),
            false,
          );
          final bytes = await file.readAsBytes();
          await PodMediaService.writeMedia(
            podPath: _path,
            displayName: name,
            bytes: bytes,
          );
          if (name != file.name) renamed[file.name] = name;
          added++;
        } on Object catch (e) {
          failed[file.name] = '$e';
        }
      }
    });

    if (added > 0 && context.mounted) context.read<MediaIndex>().invalidate();
    await reload();
    if (!context.mounted) return;

    if (failed.isNotEmpty) {
      await showErrorDialog(
        context,
        added == 0 ? 'Nothing could be added' : 'Some files were not added',
        failed.entries.map((e) => '${e.key}: ${e.value}').join('\n\n'),
      );
      return;
    }

    // A name is quietly tidied rather than refused, so that a photo straight
    // off a camera always lands. Saying so beats letting the user wonder why
    // the name on the tile is not the one they picked.

    if (renamed.isNotEmpty && context.mounted) {
      await showErrorDialog(
        context,
        renamed.length == 1
            ? 'One file was renamed'
            : 'Some files were renamed',
        'A name on the Pod can hold only letters, digits and '
        "- _ . ! ~ * ' ( ), so anything else was replaced with an "
        'underscore.\n\n'
        '${renamed.entries.map((e) => '${e.key}  →  ${e.value}').join('\n')}',
      );
    }
  }

  // Refuse to write into a folder whose own name would have to be escaped in
  // a URL, since anything put there would lose its encryption key. Such a
  // folder can only have been made by an earlier build of PhotoPod, and
  // renaming it puts everything right.

  Future<bool> _folderIsWritable(BuildContext context) async {
    final segment = unsafeSegmentOf(_path);
    if (segment == null) return true;

    await showErrorDialog(
      context,
      'This folder cannot be written to',
      'The folder "${PodMediaService.decodeName(segment)}" has a name that '
          'has to be escaped inside a web address, and anything written into '
          'it would be stored in a way PhotoPod could not read back.\n\n'
          'Rename the folder — letters, digits and '
          "- _ . ! ~ ' ( ) only — and then try again.",
    );
    return false;
  }

  /// Create a folder inside the folder being shown.

  Future<void> _newFolder(BuildContext context) async {
    if (!await _folderIsWritable(context)) return;
    if (!context.mounted) return;

    final name = await showFolderNameDialog(context);
    if (name == null || !context.mounted) return;

    await _guard(context, 'Could not create the folder', () async {
      await PodMediaOps.createFolder(_path, name);
    });
    if (context.mounted) context.read<MediaIndex>().invalidate();
    await reload();
  }

  /// Remove the selected items, after checking that is really wanted.
  ///
  /// The flat sections show items from every folder at once, so the selection
  /// is grouped by the folder each item sits in and each group is deleted in
  /// its own batch.

  Future<void> _delete(BuildContext context) async {
    final items = _selectedItems;
    if (items.isEmpty) return;

    final folders = items.where((item) => item.isFolder).length;
    final single = items.length == 1;
    final subject = single ? '"${items.first.name}"' : '${items.length} items';
    final nested = folders == 0
        ? ''
        : single
        ? ' Everything inside it goes too.'
        : ' Everything inside the $folders selected '
              '${folders == 1 ? 'folder' : 'folders'} goes too.';

    final confirmed = await showConfirmDialog(
      context,
      title: single ? 'Delete this item?' : 'Delete ${items.length} items?',
      message:
          '$subject will be removed from your Pod.$nested '
          'This cannot be undone.',
    );
    if (!confirmed || !context.mounted) return;

    final favourites = context.read<Favourites>();
    final index = context.read<MediaIndex>();

    final failed = await showWorking(
      context,
      'Deleting...',
      () => _deleteByFolder(items),
    );

    for (final item in items) {
      ThumbnailCache.instance.evict(item.url);
    }

    // Only what actually went is forgotten, so an item the server refused to
    // remove keeps its heart.

    await favourites.forget([
      for (final item in items)
        if (!failed.containsKey(item)) item.path,
    ]);
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
  // names on the server — `beach.jpg.enc.ttl` rather than `beach.jpg` — so
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

  /// Make sure the security key is available before reading or writing
  /// encrypted media, prompting for it once per session.
  ///
  /// Returns false when the key could not be obtained, in which case the
  /// caller should give up rather than fail on every file in turn.

  Future<bool> _ensureSecurityKey(BuildContext context) async {
    try {
      await getKeyFromUserIfRequired(
        context,
        const Text('Please enter your security key to unlock your album'),
      );
      if (!await KeyManager.hasSecurityKey()) return false;

      // Read the keys into memory now, while nothing else is asking for
      // them. See [PodKeys] for what happens when several callers do.

      await PodKeys.prime();
      return true;
    } on Object catch (e) {
      if (context.mounted) {
        await showErrorDialog(context, 'Security key needed', '$e');
      }
      return false;
    }
  }

  /// Run [action], reporting anything that goes wrong in a dialogue.

  Future<void> _guard(
    BuildContext context,
    String title,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Object catch (e) {
      if (context.mounted) await showErrorDialog(context, title, '$e');
    }
  }
}
