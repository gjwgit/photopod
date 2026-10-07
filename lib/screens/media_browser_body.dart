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

    final sorted = _sorted;
    final pageCount = _pageCount(sorted.length, prefs.itemsPerPage);
    final page = _page.clamp(0, pageCount - 1);
    final visible = _pageOf(sorted, page, prefs.itemsPerPage);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: _buildHeader(context),
        ),
        const Divider(height: 1),
        Expanded(
          child: _buildDropTarget(
            context,
            _buildContent(context, prefs, visible, sorted),
          ),
        ),

        // Each album scrolls on its own, so the Albums section has no pages.
        if (widget.section != LibrarySection.albums) ...[
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

  // Only the Library has a folder to put things in, so it alone takes files
  // dragged from the desktop, and only once it knows which folder that is.
  // While a drag hovers the content is outlined and says where the files
  // will go, so the drop is not a leap of faith.

  Widget _buildDropTarget(BuildContext context, Widget child) {
    final enabled =
        widget.section == LibrarySection.library && _root.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    final folder = _segmentLabels.isEmpty ? 'your album' : _segmentLabels.last;

    return DropTarget(
      enable: enabled,
      onDragEntered: (_) => updateState(() => _dragging = true),
      onDragExited: (_) => updateState(() => _dragging = false),
      onDragDone: (details) {
        updateState(() => _dragging = false);
        _dropFiles(context, details.files);
      },
      child: Stack(
        children: [
          Positioned.fill(child: child),
          if (enabled && _dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.85),
                    border: Border.all(color: scheme.primary, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_upload_outlined,
                          size: 56,
                          color: scheme.onPrimaryContainer,
                        ),
                        const Gap(12),
                        Text(
                          'Drop photos and videos to add them to $folder',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: scheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // The path trail and the toolbar share a row on a wide window and stack on
  // a narrow one, so neither has to be squeezed or scrolled on a phone.

  Widget _buildHeader(BuildContext context) {
    final files = _selectedFiles;

    final leading = widget.section.browsesFolders
        ? BreadcrumbBar(
            segments: _segmentLabels,
            onNavigate: (keep) => _goTo(
              keep == 0 ? _root : '$_root/${_segments.take(keep).join('/')}',
            ),
          )
        : _buildSectionTitle(context);

    final toolbar = MediaToolbar(
      section: widget.section,
      selectionCount: _selected.length,
      fileCount: files.length,
      allFavourite: context.read<Favourites>().containsAll(files),
      sortOption: context.read<ViewPrefs>().sortOption,
      actions: _actions(context),
      albumNames: context.read<Albums>().names,
      canRemoveFromAlbum: _inOwnAlbum && files.isNotEmpty,
      hasShared: _selectedItems.any((item) => item.isShared),
    );

    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 860
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
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_selected.isNotEmpty) updateState(_selected.clear);
        },
        child: _buildAlbums(context, prefs, favourites),
      );
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
    // because a tap on an item toggles rather than replaces the selection.

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_selected.isNotEmpty) updateState(_selected.clear);
      },
      child: prefs.viewMode == MediaViewMode.grid
          ? MediaGrid(
              items: visible,
              tileExtent: prefs.tileSize.extent,
              isSelected: (item) => _selected.contains(item.id),
              isFavourite: favourites.contains,
              onTap: (item) => _handleTap(item, visible),
              onActivate: _handleActivate,
              onToggleFavourite: (item) => _toggleFavourite(context, [item]),
            )
          : MediaList(
              items: visible,
              isSelected: (item) => _selected.contains(item.id),
              isFavourite: favourites.contains,
              onTap: (item) => _handleTap(item, visible),
              onActivate: _handleActivate,
              onToggleFavourite: (item) => _toggleFavourite(context, [item]),
            ),
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
      onShare: (album) => _shareAlbum(
        context,
        album,
        entries.firstWhere((entry) => entry.id == album).items,
      ),
      onRemoveFromAlbum: (album, item) =>
          _removeItemsFromAlbum(context, album, [item]),
      onRename: (album) => _renameAlbum(context, album),
      onDelete: (album) => _deleteAlbum(context, album),
    );
  }

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
