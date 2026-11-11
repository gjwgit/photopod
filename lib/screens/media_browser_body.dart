/// The visual side of the media browser.
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

/// The visual side of [MediaBrowserState], kept apart from the state it reads
/// so that neither file grows unwieldy.

extension MediaBrowserBody on MediaBrowserState {
  /// The whole section: the path or the section heading along the top, the
  /// items in the middle, and the page controls underneath.

  Widget _buildBrowser(BuildContext context) {
    // Watched here, at the top of the build, so that everything below can
    // simply read them: the album index feeds the sections that look across
    // the whole album, the hearts decide both what Favourites holds and which
    // tiles show one, and the albums decide what the Albums section lists.

    final prefs = context.watch<ViewPrefs>();
    context.watch<Favourites>();
    context.watch<Albums>();
    context.watch<MediaIndex>();
    context.watch<SharedWithMe>();
    context.watch<AlbumSharing>();
    final filter = context.watch<MediaFilter>();

    // A new search starts from the first page, and lets go of anything
    // selected that it hides, so that no action reaches what is not shown.

    if (filter.text != _filterText) {
      _filterText = filter.text;
      _page = 0;
      if (filter.isActive) {
        final shown = {for (final item in _source) item.id};
        _selected.removeWhere((id) => !shown.contains(id));
      }
    }

    // The timeline scrolls through everything at once, the way a camera
    // roll does, so it has no pages, and nor does the Albums section, where
    // each album scrolls on its own.

    final paged = widget.section != LibrarySection.albums && !_isTimeline;
    final sorted = _sorted;
    final pageCount = paged ? _pageCount(sorted.length, prefs.itemsPerPage) : 1;
    final page = _page.clamp(0, pageCount - 1);
    final visible = paged ? _pageOf(sorted, page, prefs.itemsPerPage) : sorted;

    return Column(
      children: [
        if (_demo) const DemoBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: _buildHeader(context),
        ),
        FilterBar(
          shown: widget.section == LibrarySection.albums ? null : sorted.length,
          total: widget.section == LibrarySection.albums
              ? null
              : _unfiltered.length,
        ),
        const Divider(height: 1),
        Expanded(
          child: _buildDropTarget(
            context,
            _buildContent(context, prefs, visible, sorted),
          ),
        ),

        if (paged) ...[
          const Divider(height: 1),
          PaginationBar(
            page: page,
            pageCount: pageCount,
            total: sorted.length,
            shown: visible.length,
            selected: _selected.length,
            onPage: (next) => updateState(() => _page = next),
          ),
        ],
      ],
    );
  }

  // The title and the toolbar share a row on a wide window and stack on a
  // narrow one, so neither has to be squeezed or scrolled on a phone.

  Widget _buildHeader(BuildContext context) {
    final files = _selectedFiles;
    final leading = _buildSectionTitle(context);

    final toolbar = MediaToolbar(
      section: widget.section,
      selectionCount: _selected.length,
      fileCount: files.length,
      allFavourite: context.read<Favourites>().containsAll(files),
      sortOption: context.read<ViewPrefs>().sortOption,
      canSort: !_isTimeline,
      actions: _actions(context),
      albumNames: context.read<Albums>().names,
      canRemoveFromAlbum: _inOwnAlbum && files.isNotEmpty,
      hasShared: _selectedItems.any((item) => item.isShared),
      multiSelect: _multiSelect,
    );

    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= wideHeaderWidth
          ? Row(
              children: [
                Expanded(child: leading),
                toolbar,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [leading, toolbar],
            ),
    );
  }

  // The flat sections have no folder to name, so the left of the header says
  // which of them is on screen and how far across the album it has looked.

  Widget _buildSectionTitle(BuildContext context) {
    final index = context.read<MediaIndex>();
    final scanned = index.scannedAt;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Icon(
            widget.section.icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const Gap(8),
          Text(
            widget.section.label,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (!index.isLoading) ...[
            const Gap(8),
            Text(
              _countLabel(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
          if (context.read<SharedWithMe>().error != null) ...[
            const Gap(8),
            Tooltip(
              message:
                  'What other people have shared with you could not be '
                  'read, so it may be missing.\n\n'
                  '${context.read<SharedWithMe>().error}',
              child: Icon(
                Icons.warning_amber_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          if (index.isTruncated) ...[
            const Gap(8),
            Tooltip(
              message:
                  'Only the first $maxScannedFolders folders of your album '
                  'were read, so some items may be missing.',
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
          if (scanned != null) ...[
            const Gap(12),
            Flexible(
              child: Text(
                'Album read at ${formatDateTime(scanned)}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // How many photos and videos the section holds, whatever the filter bar
  // is searching for, which says for itself how many of them it shows.

  String _countLabel() {
    final files = _unfiltered.where((item) => !item.isFolder).toList();
    final videos = files.where((item) => item.isVideo).length;
    final photos = files.length - videos;
    String count(int n, String noun) =>
        '${formatCount(n)} $noun${n == 1 ? '' : 's'}';
    if (photos == 0 && videos == 0) {
      return count(
        0,
        widget.section == LibrarySection.videos ? 'video' : 'photo',
      );
    }
    return [
      if (photos > 0) count(photos, 'photo'),
      if (videos > 0) count(videos, 'video'),
    ].join(', ');
  }

  Widget _buildContent(
    BuildContext context,
    ViewPrefs prefs,
    List<MediaItem> visible,
    List<MediaItem> all,
  ) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _errorText;
    if (error != null) {
      return _buildMessage(
        context,
        icon: Icons.cloud_off,
        title: 'Could not read your album',
        message: error,
        action: FilledButton.icon(
          onPressed: () => reload(force: true),
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }

    final favourites = context.read<Favourites>();

    // Favourites has its own section and is not listed among the albums, so
    // the Albums section is empty until the user makes an album or someone
    // shares one.

    if (widget.section == LibrarySection.albums) {
      if (context.read<Albums>().names.isEmpty &&
          context.read<SharedWithMe>().albums.isEmpty) {
        return _buildMessage(
          context,
          icon: widget.section.icon,
          title: 'No albums yet',
          message: _emptyMessage(),
        );
      }
      if (_albumEntries(context).isEmpty) return _buildNoMatches(context);
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_selected.isNotEmpty) updateState(_selected.clear);
        },
        child: _buildAlbums(context, prefs, favourites),
      );
    }

    if (all.isEmpty && context.read<MediaFilter>().isActive) {
      return _buildNoMatches(context);
    }

    if (all.isEmpty) {
      return _buildMessage(
        context,
        icon: widget.section.icon,
        title: 'Nothing here yet',
        message: _emptyMessage(),
      );
    }

    // Tapping the background is how the selection is cleared, which matters
    // most with Select several on, when a tap on an item toggles rather than
    // replaces the selection.

    final shared = context.read<SharedWithMe>();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_selected.isNotEmpty) updateState(_selected.clear);
      },
      child: _isTimeline
          ? _buildTimeline(context, prefs, favourites, all)
          : prefs.viewMode == MediaViewMode.grid
          ? MediaGrid(
              items: visible,
              tileExtent: prefs.tileSize.extent,
              isSelected: (item) => _selected.contains(item.id),
              isFavourite: favourites.contains,
              isSharedOut: (item) => shared.isSharedOut(item.url),
              multiSelect: _multiSelect,
              onTap: (item) => _handleTap(item, visible),
              onActivate: _handleActivate,
              onToggleFavourite: (item) => _toggleFavourite(context, [item]),
              onInfo: (item) => showInfoDialog(context, item),
            )
          : MediaList(
              items: visible,
              isSelected: (item) => _selected.contains(item.id),
              isFavourite: favourites.contains,
              isSharedOut: (item) => shared.isSharedOut(item.url),
              multiSelect: _multiSelect,
              onTap: (item) => _handleTap(item, visible),
              onActivate: _handleActivate,
              onToggleFavourite: (item) => _toggleFavourite(context, [item]),
            ),
    );
  }

  // The photos and videos are grouped under the day they are dated, the
  // latest day first, with the memories along the top.

  Widget _buildTimeline(
    BuildContext context,
    ViewPrefs prefs,
    Favourites favourites,
    List<MediaItem> all,
  ) {
    final files = all.where((item) => !item.isFolder).toList();

    return MediaTimeline(
      groups: groupByDay(files),
      memories: memoriesOf(files),
      tileExtent: prefs.tileSize.extent,
      isSelected: (item) => _selected.contains(item.id),
      isFavourite: favourites.contains,
      isSharedOut: (item) => context.read<SharedWithMe>().isSharedOut(item.url),
      multiSelect: _multiSelect,
      onTap: (item) => _handleTap(item, all),
      onActivate: _handleActivate,
      onToggleFavourite: (item) => _toggleFavourite(context, [item]),
      onInfo: (item) => showInfoDialog(context, item),
      onOpenMemory: (memory) =>
          _handleActivate(memory.items.first, memory.items),
    );
  }

  Widget _buildAlbums(
    BuildContext context,
    ViewPrefs prefs,
    Favourites favourites,
  ) {
    final entries = _albumEntries(context);

    return AlbumList(
      albums: entries,
      tileExtent: prefs.tileSize.extent,
      isSelected: (album, item) =>
          album == _selectedAlbum && _selected.contains(item.id),
      isFavourite: favourites.contains,
      isSharedOut: (item) => context.read<SharedWithMe>().isSharedOut(item.url),
      multiSelect: _multiSelect,
      onTap: (album, item) => _handleAlbumTap(
        album,
        item,
        entries.firstWhere((entry) => entry.id == album).items,
      ),
      onActivate: (album, item) => _handleActivate(
        item,
        entries.firstWhere((entry) => entry.id == album).items,
      ),
      onToggleFavourite: (item) => _toggleFavourite(context, [item]),
      onInfo: (item) => showInfoDialog(context, item),
      onShare: (album) => _shareAlbum(
        context,
        album,
        entries.firstWhere((entry) => entry.id == album).items,
      ),
      onRemoveFromAlbum: (album, item) =>
          _removeItemsFromAlbum(context, album, [item]),
      onRename: (album) => _renameAlbum(context, album),
      onDelete: (album) => _deleteAlbum(context, album),
      onDecline: (album) => _declineSharedAlbum(context, album),
    );
  }

  // The search hides everything, which says so, and offers to clear it,
  // rather than claim the section is empty.

  Widget _buildNoMatches(BuildContext context) => _buildMessage(
    context,
    icon: Icons.search_off,
    title: 'Nothing matches',
    message:
        'Nothing here matches "${context.read<MediaFilter>().text.trim()}".',
    action: FilledButton.icon(
      onPressed: context.read<MediaFilter>().clear,
      icon: const Icon(Icons.clear),
      label: const Text('Clear the filter'),
    ),
  );

  String _emptyMessage() => switch (widget.section) {
    LibrarySection.library =>
      'This folder holds no photos, no videos and no subfolders. Use Add, or '
          'drag photos and videos here, to put some in.',
    LibrarySection.albums =>
      'There are no albums yet. Select some photos or videos and use Add to '
          'album to make one.',
    LibrarySection.favourites =>
      'Nothing carries a heart yet. Select a photo or a video anywhere in '
          'your album and tap the heart to bring it here.',
    LibrarySection.videos =>
      'There are no videos anywhere in your album yet. Use Add in the '
          'Library to put some in.',
    LibrarySection.people => 'Nobody to show.',
    LibrarySection.maps => 'Nothing to map.',
  };

  Widget _buildMessage(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const Gap(16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Gap(8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(message, textAlign: TextAlign.center),
          ),
          if (action != null) ...[const Gap(20), action],
        ],
      ),
    ),
  );

  static int _pageCount(int total, int perPage) =>
      total == 0 ? 1 : ((total - 1) ~/ perPage) + 1;

  static List<MediaItem> _pageOf(List<MediaItem> items, int page, int perPage) {
    final start = page * perPage;
    if (start >= items.length) return const [];
    final end = start + perPage;
    return items.sublist(start, end > items.length ? items.length : end);
  }
}
