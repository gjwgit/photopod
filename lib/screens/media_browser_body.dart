/// Lay out the media browser.
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
  /// The whole section: path and toolbar along the top, the items in the
  /// middle, and the page controls underneath.

  Widget _buildBrowser(BuildContext context) {
    final prefs = context.watch<ViewPrefs>();
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
    final breadcrumbs = BreadcrumbBar(
      segments: _segmentLabels,
      onNavigate: (keep) =>
          _goTo(keep == 0 ? _root : '$_root/${_segments.take(keep).join('/')}'),
      onUp: _segments.isEmpty
          ? null
          : () => _goTo(
              _segments.length == 1
                  ? _root
                  : '$_root/'
                        '${_segments.take(_segments.length - 1).join('/')}',
            ),
    );

    final toolbar = MediaToolbar(
      kind: widget.kind,
      selectionCount: _selected.length,
      canPreview: _selectedItems.any((item) => !item.isFolder),
      sortOption: context.watch<ViewPrefs>().sortOption,
      actions: _actions(context),
    );

    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 860
          ? Row(
              children: [
                Expanded(child: breadcrumbs),
                toolbar,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [breadcrumbs, toolbar],
            ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ViewPrefs prefs,
    List<MediaItem> visible,
    List<MediaItem> all,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _error;
    if (error != null) {
      return _buildMessage(
        context,
        icon: Icons.cloud_off,
        title: 'Could not read this folder',
        message: error,
        action: FilledButton.icon(
          onPressed: reload,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }

    if (all.isEmpty) {
      return _buildMessage(
        context,
        icon: widget.kind.icon,
        title: 'Nothing here yet',
        message:
            'This folder holds no ${widget.kind.label.toLowerCase()} '
            'and no subfolders. Use Add to put some in.',
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
              isSelected: (item) => _selected.contains(item.id),
              onTap: (item) => _handleTap(item, visible),
              onActivate: _handleActivate,
            )
          : MediaList(
              items: visible,
              isSelected: (item) => _selected.contains(item.id),
              onTap: (item) => _handleTap(item, visible),
              onActivate: _handleActivate,
            ),
    );
  }

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
