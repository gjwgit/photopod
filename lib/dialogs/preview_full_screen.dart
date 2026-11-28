/// The preview as a phone or tablet shows it: full screen, swiping between
/// photos.
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

part of 'preview_dialog.dart';

/// The preview filling the screen, as a tap on a photo opens it on a phone or
/// tablet.
///
/// A bar along the top names the photo or video on show and closes the
/// preview; a bar along the bottom offers what the toolbar would offer for
/// it. Between them the photos and videos of [items] sit side by side, to be
/// swiped through without leaving the preview. A photo zoomed in pans rather
/// than swipes, until it is zoomed back out.

class _FullScreenPreview extends StatefulWidget {
  const _FullScreenPreview({
    required this.items,
    required this.initialIndex,
    this.actions,
  });

  /// The files that can be swiped through, in display order.

  final List<MediaItem> items;

  /// Where in [items] the preview starts.

  final int initialIndex;

  /// What can be done to the file on show, beyond looking at it.

  final PreviewActions? actions;

  @override
  State<_FullScreenPreview> createState() => _FullScreenPreviewState();
}

class _FullScreenPreviewState extends State<_FullScreenPreview> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  /// Whether the photo on show is zoomed in, when a swipe pans it instead of
  /// stepping to the next.

  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final theme = Theme.of(context);

    // A photo with a title is headed by it, and its file name moves down
    // among the details, as in the dialogue the desktop shows.

    final title = MediaCatalog.titleOf(item.path)?.text;
    final details = [
      if (title != null) item.name,
      if (widget.items.length > 1) '${_index + 1} of ${widget.items.length}',
      if (item.modified != null) formatDateTime(item.modified),
    ].join('  ·  ');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title ?? item.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            if (details.isNotEmpty)
              Text(
                details,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),

      // The messages shown when a file cannot be opened are written on the
      // black background, so they are drawn light.
      body: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white70),
        child: PageView.builder(
          controller: _pages,
          physics: _zoomed
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          itemCount: widget.items.length,
          onPageChanged: (index) => setState(() {
            _index = index;
            _zoomed = false;
          }),
          itemBuilder: (context, index) {
            final each = widget.items[index];
            return _PreviewBody(
              key: ValueKey(each.id),
              item: each,
              onZoomed: (zoomed) {
                if (mounted && index == _index) {
                  setState(() => _zoomed = zoomed);
                }
              },
            );
          },
        ),
      ),
      bottomNavigationBar: _PreviewBottomBar(
        item: item,
        actions: widget.actions,
        onChanged: _redraw,
      ),
    );
  }
}

/// The bar along the bottom of the full-screen preview: what can be done to
/// the photo or video on show. Favourite, Share, Get Info and Delete sit in
/// the bar, and the rest wait in a menu at its end, so that the bar fits a
/// phone held upright.

class _PreviewBottomBar extends StatelessWidget {
  const _PreviewBottomBar({
    required this.item,
    required this.actions,
    required this.onChanged,
  });

  /// The photo or video on show.

  final MediaItem item;

  /// What can be done to it beyond looking, if anything.

  final PreviewActions? actions;

  /// Called once an action is done, so the preview can draw itself again.

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final favourites = context.watch<Favourites>();
    final favourite = favourites.contains(item);
    final actions = this.actions;

    // What the toolbar would offer for this one item, as in the header of
    // the desktop's dialogue.

    final own = !item.isShared;
    final analysable = actions != null && own && item.isPhoto;
    final podShareable = actions != null && own;
    final routes = shareRoutesFor([item]);

    final folded = <_HeaderAction>[
      if (analysable) ...[_HeaderAction.identify, _HeaderAction.tag],
      if (podShareable) _HeaderAction.podShare,
      _HeaderAction.download,
    ];

    return BottomAppBar(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(
              favourite ? Icons.favorite : Icons.favorite_border,
              color: favourite ? const Color(0xFFE53935) : null,
            ),
            tooltip: favourite ? 'Remove from Favourites' : 'Add to Favourites',
            onPressed: () => actions == null
                ? favourites.toggleAll([item])
                : actions.onToggleFavourite(item),
          ),
          if (routes.isNotEmpty) _ShareCopyButton(item: item, routes: routes),
          IconButton(
            icon: Icon(_HeaderAction.info.icon),
            tooltip: _HeaderAction.info.tooltip,
            onPressed: () => _runPreviewAction(
              context,
              _HeaderAction.info,
              item,
              actions,
              onChanged,
            ),
          ),
          if (actions != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: own ? 'Delete' : 'Decline this shared item',
              onPressed: () => _deleteFromPreview(context, item, actions),
            ),
          PopupMenuButton<_HeaderAction>(
            icon: const Icon(Icons.more_horiz),
            tooltip: 'More',
            onSelected: (action) =>
                _runPreviewAction(context, action, item, actions, onChanged),
            itemBuilder: (context) => [
              for (final action in folded)
                PopupMenuItem(
                  value: action,
                  child: ListTile(
                    leading: Icon(action.icon),
                    title: Text(action.label),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
