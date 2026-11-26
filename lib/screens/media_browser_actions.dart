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
    onDelete: () => _delete(context),
    onDuplicate: () => _duplicate(context),
    onRename: () => _rename(context),
    onShare: () => _share(context),
    onShareCopy: (route, origin) =>
        shareCopies(context, _selectedFiles, route, origin: origin),
    onView: () => showViewOptionsDialog(context),
    onPreview: () => _previewFirst(context),
    onGetInfo: () => _getInfo(context),
    onDownload: () => downloadMedia(context, _selectedFiles),
    onIdentifyPeople: () => _identifyPeople(context, _selectedFiles),
    onTagPhotos: () => _tagPhotos(context, _selectedFiles),
    onToggleFavourite: () => _toggleFavourite(context, _selectedFiles),
    onAddToAlbum: (album) => _addToAlbum(context, album, _selectedFiles),
    onCreateAlbum: () => _createAlbum(context, _selectedFiles),
    onRemoveFromAlbum: () => _removeFromAlbum(context),
    onRefresh: () => reload(force: true),
    onToggleMultiSelect: _toggleMultiSelect,
    onSort: (option) {
      context.read<ViewPrefs>().setSortOption(option);
      updateState(() => _page = 0);
    },
  );

  /// What the preview offers to do to the photo or video it shows, which is
  /// what the toolbar offers to do to a selection of one.
  ///
  /// The dialogues these open are pushed above the preview, so the preview
  /// stays open behind them, except for Delete: the preview closes first,
  /// since what it shows is about to go.

  PreviewActions _previewActions(BuildContext context) => PreviewActions(
    onToggleFavourite: (item) => _toggleFavourite(context, [item]),
    onIdentifyPeople: (item) => _identifyPeople(context, [item]),
    onTagPhotos: (item) => _tagPhotos(context, [item]),
    onPodShare: (item) => _share(context, [item]),
    onDelete: (item) => _delete(context, [item]),
  );

  /// Share [items] on the Pod, the selected items unless told otherwise, then
  /// read the permission log again so that what was just shared carries the
  /// two-people mark straight away.

  Future<void> _share(BuildContext context, [List<MediaItem>? items]) async {
    if (await _needsPod(context, 'share photos and videos')) return;
    if (!context.mounted) return;
    final shared = context.read<SharedWithMe>();
    await showShareDialog(context, items ?? _selectedItems);
    await shared.load(force: true);
  }

  /// Have the PhotoPod Analyser find the people in the photos among [items].

  Future<void> _identifyPeople(BuildContext context, List<MediaItem> items) =>
      _askAnalyser(
        context,
        context.read<People>(),
        items,
        what: 'People are found',
        doing: 'Identifying the people in',
        shownIn: 'People, and in Get Info,',
      );

  /// Have the PhotoPod Analyser tag the photos among [items].

  Future<void> _tagPhotos(BuildContext context, List<MediaItem> items) =>
      _askAnalyser(
        context,
        context.read<PhotoTags>(),
        items,
        what: 'Tags are found',
        doing: 'Tagging',
        shownIn: 'Tags, and in Get Info,',
      );

  /// Handle a tap on [item], one of the items in [visible].
  ///
  /// Normally a tap selects that one item in place of whatever was selected,
  /// and tapping it again lets it go. With **Select several** on, a tap adds
  /// the item to the selection or takes it out again, which makes multiple
  /// selection work the same way with a mouse as with a finger, and holding
  /// shift selects everything between the last tap and this one. Tapping the
  /// background clears the selection either way.

  void _handleTap(MediaItem item, List<MediaItem> visible) {
    final index = visible.indexOf(item);
    _lastTapped = item.id;

    if (!_multiSelect) {
      updateState(() {
        final only = _selected.length == 1 && _selected.contains(item.id);
        _selected.clear();
        if (!only) _selected.add(item.id);
        if (index >= 0) _anchor = index;
      });
      return;
    }

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

  /// Turn **Select several** on or off. Turning it off keeps only the item
  /// tapped last, so that the selection again holds a single item.

  void _toggleMultiSelect() {
    updateState(() {
      _multiSelect = !_multiSelect;
      if (_multiSelect || _selected.length < 2) return;
      final last = _lastTapped;
      final keep = last != null && _selected.contains(last);
      _selected.clear();
      if (keep) _selected.add(last);
    });
  }

  /// Handle a double tap: preview the file.
  ///
  /// The preview can step through [siblings], which defaults to every file
  /// this section shows, across all pages, in the order they are displayed.

  Future<void> _handleActivate(
    MediaItem item, [
    List<MediaItem>? siblings,
  ]) async {
    if (item.isFolder || !mounted) return;
    await showPreviewDialog(
      context,
      item,
      items: siblings ?? _sortedFiles,
      actions: _previewActions(context),
    );
  }

  /// Preview the first selected file, ignoring any selected folders.

  Future<void> _previewFirst(BuildContext context) async {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    await showPreviewDialog(
      context,
      files.first,
      items: _sortedFiles,
      actions: _previewActions(context),
    );
  }

  /// Describe the first selected file.
  ///
  /// The tiles carry no captions, so this is the one place the name, the
  /// size, the dates and the camera settings are all written out.

  Future<void> _getInfo(BuildContext context) async {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    await showInfoDialog(context, files.first);
  }

  /// Add a heart to [items], or take it away from all of them.

  Future<void> _toggleFavourite(
    BuildContext context,
    List<MediaItem> items,
  ) async {
    if (items.isEmpty) return;

    final favourites = context.read<Favourites>();
    final saved = await favourites.toggleAll(items);
    if (!context.mounted) return;

    // Favourites can be shared like any other album, in which case the
    // photos given or losing a heart are shared or unshared to match.

    if (saved) {
      await _syncSharing(context);
      return;
    }

    await showErrorDialog(
      context,
      'Could not save your favourites',
      'The hearts are kept in a file in your Pod, and that file could not be '
          'written.\n\n${favourites.error ?? ''}',
    );
  }

  /// Have the analyser the user chose look at the selected photos, and only
  /// those, for [section]: the people in them, or their tags. The user is
  /// asked to choose one, with how private each keeps the photos, the first
  /// time. What it finds comes back in the background, and shows in the
  /// section and in Get Info as it does.

  Future<void> _askAnalyser(
    BuildContext context,
    AnalyserSection section,
    List<MediaItem> items, {
    required String what,
    required String doing,
    required String shownIn,
  }) async {
    final photos = [
      for (final item in items)
        if (item.isPhoto && !item.isShared) item,
    ];
    if (photos.isEmpty) {
      await showErrorDialog(
        context,
        'No photos selected',
        '$what in your own photos. Select one or more of them.',
      );
      return;
    }
    final backend = await chosenAnalyser(context);
    if (backend == null || !context.mounted) return;
    if (!_demo && !await _ensureSecurityKey(context)) return;
    if (!context.mounted) return;

    unawaited(section.analyse(photos, backend: backend));
    final count = photos.length == 1 ? 'one photo' : '${photos.length} photos';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          '$doing $count with ${backend.label} (${backend.privacy.toLowerCase()}). '
          'They show in $shownIn as they are found.',
        ),
      ),
    );
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

  /// Whether the sample album is showing, in which case [what] cannot be
  /// done, and the user is told why and how to do it for real.
  ///
  /// The samples are part of the app, not files in a Pod, so anything that
  /// writes to a Pod has nowhere to write. Hearts and albums still work on
  /// the samples, in memory, so that a visitor can try them.

  Future<bool> _needsPod(BuildContext context, String what) async {
    if (!_demo) return false;
    await showErrorDialog(
      context,
      'Log in to $what',
      'These are sample photos and videos, included with PhotoPod to show '
          'what it can do. They are not stored in a Pod.\n\n'
          'Log in to $what in your own Pod.',
    );
    return true;
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
