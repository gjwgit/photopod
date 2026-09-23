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
    // simply read them: the album index feeds the two flat sections, and the
    // hearts decide both what Favourites holds and which tiles show one.

    final prefs = context.watch<ViewPrefs>();
    context.watch<Favourites>();
    context.watch<MediaIndex>();

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
        Expanded(child: _buildContent(context, prefs, visible, sorted)),
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
            onUp: _segments.isEmpty
                ? null
                : () => _goTo(
                    _segments.length == 1
                        ? _root
                        : '$_root/'
                              '${_segments.take(_segments.length - 1).join('/')}',
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

    if (all.isEmpty) {
      return _buildMessage(
        context,
        icon: widget.section.icon,
        title: 'Nothing here yet',
        message: _emptyMessage(),
      );
    }

    final favourites = context.read<Favourites>();

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

  String _emptyMessage() => switch (widget.section) {
    LibrarySection.library =>
      'This folder holds no photos, no videos and no subfolders. Use Add to '
          'put some in.',
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
