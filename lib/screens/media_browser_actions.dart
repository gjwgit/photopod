/// Selection and the toolbar actions.
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
    onRefresh: reload,
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
    final files = _selectedItems.where((item) => !item.isFolder).toList();
    if (files.isEmpty) {
      await showErrorDialog(
        context,
        'Nothing to preview',
        'Select a ${widget.kind.noun} first. Folders cannot be previewed, '
            'only opened.',
      );
      return;
    }
    if (context.mounted) await showPreviewDialog(context, files.first);
  }

  /// Add files from this device to the folder being shown.
  ///
  /// The picker is limited to the formats of the section the user is in, and
  /// a name that would not survive being put in a URL is tidied up rather
  /// than refused, so that a photo straight off a camera always lands.

  Future<void> _addFiles(BuildContext context) async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: widget.kind.extensions.toList(),
        dialogTitle: 'Add ${widget.kind.label.toLowerCase()}',
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
    var added = 0;

    await showWorking(context, 'Adding to your Pod...', () async {
      for (final file in picked) {
        try {
          if (kindOf(file.name) != widget.kind) {
            failed[file.name] = 'not a ${widget.kind.noun} PhotoPod supports';
            continue;
          }
          final name = await PodMediaOps.freeName(
            _path,
            _tidyName(file.name),
            false,
          );
          final bytes = await file.readAsBytes();
          await PodMediaService.writeMedia(
            podPath: _path,
            displayName: name,
            bytes: bytes,
          );
          added++;
        } on Object catch (e) {
          failed[file.name] = '$e';
        }
      }
    });

    await reload();
    if (!context.mounted) return;

    if (failed.isNotEmpty) {
      await showErrorDialog(
        context,
        added == 0 ? 'Nothing could be added' : 'Some files were not added',
        failed.entries.map((e) => '${e.key}: ${e.value}').join('\n\n'),
      );
    }
  }

  /// Create a folder inside the folder being shown.

  Future<void> _newFolder(BuildContext context) async {
    final name = await showFolderNameDialog(context);
    if (name == null || !context.mounted) return;

    await _guard(context, 'Could not create the folder', () async {
      await PodMediaOps.createFolder(_path, name);
    });
    await reload();
  }

  /// Remove the selected items, after checking that is really wanted.

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

    final result = await showWorking(
      context,
      'Deleting...',
      () => PodMediaOps.deleteAll(_path, items),
    );

    for (final item in items) {
      ThumbnailCache.instance.evict(item.url);
    }
    await reload();

    if (context.mounted && result.hasFailures) {
      await showErrorDialog(
        context,
        'Some items could not be deleted',
        result.failed.entries.map((e) => '${e.key}: ${e.value}').join('\n\n'),
      );
    }
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
      return await KeyManager.hasSecurityKey();
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

  // Replace anything that cannot appear in a Solid resource name, so that a
  // file called "holiday #1 (50%).jpg" becomes one that can be addressed by
  // URL.

  static String _tidyName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|#%\x00-\x1f]'), '_').trim();
}
