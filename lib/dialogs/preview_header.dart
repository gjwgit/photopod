/// The preview's header, with what can be done to the file on show.
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

/// What the preview offers to do to the photo or video it shows, handed in by
/// the section it was opened from: the Library, Favourites or Albums, whose
/// toolbar offers the same to a selection. Without these, as from People,
/// Tags or Maps, the preview offers Favourite, Share, Download and Get Info.

class PreviewActions {
  const PreviewActions({
    required this.onToggleFavourite,
    required this.onIdentifyPeople,
    required this.onTagPhotos,
    required this.onPodShare,
    required this.onDelete,
  });

  /// Add a heart to the file, or take it away.

  final Future<void> Function(MediaItem item) onToggleFavourite;

  /// Have the PhotoPod Analyser find the people in the photo.

  final Future<void> Function(MediaItem item) onIdentifyPeople;

  /// Have the PhotoPod Analyser tag the photo with what it shows.

  final Future<void> Function(MediaItem item) onTagPhotos;

  /// Give other Solid users access to the file on the Pod.

  final Future<void> Function(MediaItem item) onPodShare;

  /// Delete the file, or decline it if it was shared with the user. Called
  /// once the preview has closed.

  final Future<void> Function(MediaItem item) onDelete;
}

/// The line along the top of the preview: what is on show, and what can be
/// done to it.

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({
    required this.item,
    required this.position,
    required this.actions,
    required this.onChanged,
  });

  /// The photo or video on show.

  final MediaItem item;

  /// Where it is among those the arrows step through, such as "3 of 12", or
  /// null when it is the only one.

  final String? position;

  /// What can be done to it beyond looking, if anything.

  final PreviewActions? actions;

  /// Called once an action is done, so the preview can draw itself again: a
  /// title may have been changed in Get Info.

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final favourites = context.watch<Favourites>();
    final favourite = favourites.contains(item);
    final actions = this.actions;

    // A photo with a title is headed by it, and its file name moves down
    // among the details; one without is headed by its file name.

    final title = MediaCatalog.titleOf(item.path)?.text;
    final details = [
      if (title != null) item.name,
      ?position,
      if (item.size != null) formatBytes(item.size),
      if (item.modified != null) formatDateTime(item.modified),
    ].join('  ·  ');

    // The dialogue is at most 90% of the screen wide, and the title needs
    // some of that, so below this width the header keeps only Favourite,
    // Share, Delete and Close beside the title and folds the rest into a
    // menu. That is the case on every phone held upright.

    final compact =
        MediaQuery.sizeOf(context).width * 0.9 < _compactHeaderWidth;

    // What the toolbar would offer for this one item. Only the owner's own
    // photos go to the Analyser, and only the owner can share an item on the
    // Pod; deleting something shared with the user declines it instead.

    final own = !item.isShared;
    final analysable = actions != null && own && item.isPhoto;
    final podShareable = actions != null && own;
    final routes = shareRoutesFor([item]);

    final folded = <_HeaderAction>[
      if (analysable) ...[_HeaderAction.identify, _HeaderAction.tag],
      if (podShareable) _HeaderAction.podShare,
      _HeaderAction.download,
      _HeaderAction.info,
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 12, compact ? 0 : 8, 12),
      child: Row(
        children: [
          if (!compact) ...[
            Icon(
              item.isVideo ? Icons.movie : Icons.image,
              color: Theme.of(context).colorScheme.primary,
            ),
            const Gap(12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title ?? item.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              favourite ? Icons.favorite : Icons.favorite_border,
              color: favourite ? const Color(0xFFE53935) : null,
            ),
            tooltip: favourite ? 'Remove from Favourites' : 'Add to Favourites',

            // The browser's own handler also shares or unshares the photo
            // when Favourites is a shared album; without one, the heart is
            // simply toggled.
            onPressed: () => actions == null
                ? favourites.toggleAll([item])
                : actions.onToggleFavourite(item),
          ),
          if (!compact)
            for (final action in folded.take(folded.length - 2))
              _actionButton(context, action),
          if (routes.isNotEmpty) _ShareCopyButton(item: item, routes: routes),
          if (actions != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: own ? 'Delete' : 'Decline this shared item',
              onPressed: () => _delete(context),
            ),
          if (compact)
            PopupMenuButton<_HeaderAction>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More',
              onSelected: (action) => _run(context, action),
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
            )
          else ...[
            _actionButton(context, _HeaderAction.download),
            _actionButton(context, _HeaderAction.info),
          ],
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(BuildContext context, _HeaderAction action) =>
      IconButton(
        icon: Icon(action.icon),
        tooltip: action.tooltip,
        onPressed: () => _run(context, action),
      );

  Future<void> _run(BuildContext context, _HeaderAction action) =>
      _runPreviewAction(context, action, item, actions, onChanged);

  void _delete(BuildContext context) =>
      _deleteFromPreview(context, item, actions);
}

/// Do [action] to [item], the file on show, then call [onChanged] so the
/// preview can draw itself again: a title may have been changed in Get Info,
/// or a share made.

Future<void> _runPreviewAction(
  BuildContext context,
  _HeaderAction action,
  MediaItem item,
  PreviewActions? actions,
  VoidCallback onChanged,
) async {
  switch (action) {
    case _HeaderAction.identify:
      await actions?.onIdentifyPeople(item);
    case _HeaderAction.tag:
      await actions?.onTagPhotos(item);
    case _HeaderAction.podShare:
      await actions?.onPodShare(item);
    case _HeaderAction.download:
      await downloadMedia(context, [item]);
    case _HeaderAction.info:
      await showInfoDialog(context, item);
  }
  if (context.mounted) onChanged();
}

/// Close the preview, then delete [item], what it was showing. The browser
/// asks for confirmation as it does from the toolbar, by which time the
/// preview has gone, so the question is asked over the album rather than
/// over the photo about to be removed.

void _deleteFromPreview(
  BuildContext context,
  MediaItem item,
  PreviewActions? actions,
) {
  final onDelete = actions?.onDelete;
  if (onDelete == null) return;
  Navigator.of(context).pop();
  onDelete(item);
}

/// How wide the preview must be for its header to show every button beside
/// the title.

const double _compactHeaderWidth = 760;

/// What the header offers besides Favourite, Share, Delete and Close. On a
/// narrow screen these go into a menu.

enum _HeaderAction {
  identify(Icons.face_outlined, 'Identify People', 'Identify People'),
  tag(Icons.sell_outlined, 'Tag Photo', 'Tag Photo'),
  podShare(
    podShareIcon,
    'Pod Share',
    'Pod Share: give other Solid users access',
  ),
  download(Icons.download_outlined, 'Download', 'Download the original'),
  info(Icons.info_outline, 'Get Info', 'Get Info');

  const _HeaderAction(this.icon, this.label, this.tooltip);

  final IconData icon;
  final String label;
  final String tooltip;
}

/// The preview's Share button, which hands a copy of the photo or video to
/// another application: Signal, WhatsApp, Teams, email, or anything that
/// takes a paste.
///
/// It wears the platform's own share icon so that it reads as the share
/// button found in every other app. Sharing on the Pod by WebID is another
/// thing altogether and has an icon of its own; see podShareIcon.
///
/// Where the platform offers more than one route, as on the desktop with its
/// share sheet and its clipboard, the button opens a menu of them; where it
/// offers one, as on a phone, the button goes straight there.

class _ShareCopyButton extends StatelessWidget {
  const _ShareCopyButton({required this.item, required this.routes});

  final MediaItem item;
  final List<ShareRoute> routes;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.adaptive.share);
    const tooltip = 'Share a copy with another app';

    if (routes.length == 1) {
      return IconButton(
        icon: icon,
        tooltip: tooltip,
        onPressed: () => _follow(context, routes.single),
      );
    }

    return PopupMenuButton<ShareRoute>(
      icon: icon,
      tooltip: tooltip,
      onSelected: (route) => _follow(context, route),
      itemBuilder: (context) => [
        for (final route in routes)
          PopupMenuItem(
            value: route,
            child: ListTile(
              leading: Icon(shareRouteIcon(route)),
              title: Text(shareRouteLabel(route)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  Future<void> _follow(BuildContext context, ShareRoute route) =>
      shareCopies(context, [item], route, origin: _originOf(context));

  // Where the button is on screen, for the popover the iPad and macOS hang
  // their share sheet from.

  static Rect? _originOf(BuildContext context) {
    if (!context.mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}
