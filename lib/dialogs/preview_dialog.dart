/// Show a photo or play a video full size.
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

library;

import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:gap/gap.dart';
import 'package:provider/provider.dart';

import 'package:photopod/constants/app.dart' show podShareIcon;
import 'package:photopod/constants/media.dart';
import 'package:photopod/dialogs/download_media.dart';
import 'package:photopod/dialogs/info_dialog.dart';
import 'package:photopod/dialogs/share_media.dart';
import 'package:photopod/models/favourites.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/media_catalog.dart';
import 'package:photopod/services/pod_media_service.dart';
import 'package:photopod/services/thumbnail_cache.dart';
import 'package:photopod/utils/formatting.dart';
import 'package:photopod/widgets/media_thumbnail.dart';
import 'package:photopod/widgets/video_preview.dart';

part 'preview_route.dart';

/// Preview [item] in a modal dialogue.
///
/// Photos can be pinched or scrolled to zoom; videos get playback controls.
/// A photo is shown from its large rendition, big enough to fill the screen
/// and far quicker to fetch than the original, with the grid's thumbnail
/// standing in until it arrives. Once the photo is zoomed in, the original is
/// fetched as well and drawn over the rendition, so that the detail stays
/// sharp. A video needs the whole file to play, so it is fetched in full.
///
/// When [items] is given, arrows either side of the preview (and the left and
/// right arrow keys) step to the previous and next photo or video in it.
/// Folders and files PhotoPod cannot show are skipped.
///
/// When [item]'s thumbnail is on screen the dialogue grows out of it as it
/// opens. Stepping between files inside the dialogue is not animated.

Future<void> showPreviewDialog(
  BuildContext context,
  MediaItem item, {
  List<MediaItem>? items,
  PreviewActions? actions,
}) {
  final playable = (items ?? const <MediaItem>[])
      .where((each) => each.kind != null)
      .toList();
  var index = playable.indexWhere((each) => each.id == item.id);
  if (index < 0) {
    playable
      ..clear()
      ..add(item);
    index = 0;
  }

  // What showDialog would do, but with a route of PhotoPod's own so that the
  // dialogue can grow out of the tile that was opened.

  final navigator = Navigator.of(context, rootNavigator: true);
  final contentKey = GlobalKey();
  return navigator.push(
    _PreviewRoute(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierColor:
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      origin: MediaThumbnail.rectOf(item),
      contentKey: contentKey,
      builder: (context) => _PreviewDialog(
        items: playable,
        initialIndex: index,
        contentKey: contentKey,
        actions: actions,
      ),
    ),
  );
}

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

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({
    required this.items,
    required this.initialIndex,
    required this.contentKey,
    this.actions,
  });

  /// The files the arrows step through, in display order.

  final List<MediaItem> items;

  /// Where in [items] the preview starts.

  final int initialIndex;

  /// Marks the panel the opening transition grows.

  final GlobalKey contentKey;

  /// What can be done to the file on show, beyond looking at it.

  final PreviewActions? actions;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  late int _index;
  Uint8List? _bytes;
  String? _error;

  /// The original photo, fetched once the preview is first zoomed in.

  Uint8List? _original;
  bool _originalRequested = false;

  final _transform = TransformationController();

  MediaItem get _item => widget.items[_index];

  bool get _hasPrevious => _index > 0;

  bool get _hasNext => _index < widget.items.length - 1;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _transform.addListener(_onTransform);
    _load();
  }

  @override
  void dispose() {
    _transform
      ..removeListener(_onTransform)
      ..dispose();
    super.dispose();
  }

  /// Move [step] places through the list and fetch the file found there.

  void _go(int step) {
    final next = _index + step;
    if (next < 0 || next >= widget.items.length) return;
    setState(() {
      _index = next;
      _bytes = null;
      _error = null;
      _original = null;
      _originalRequested = false;
    });
    _transform.value = Matrix4.identity();
    _load();
  }

  // Fetch the original the first time the photo is zoomed in. An animated GIF
  // is already previewed from its original, so it needs nothing more.

  void _onTransform() {
    if (_originalRequested || _bytes == null) return;
    if (_item.isVideo || isGif(_item.name)) return;
    if (_transform.value.getMaxScaleOnAxis() <= 1.01) return;
    _originalRequested = true;
    _loadOriginal();
  }

  Future<void> _loadOriginal() async {
    final item = _item;
    try {
      final bytes = await ThumbnailCache.instance.original(item);
      if (mounted && identical(item, _item)) {
        setState(() => _original = bytes);
      }
    } on Object catch (e) {
      // The large rendition is still on screen, so the zoom carries on with
      // that rather than reporting an error.

      debugPrint('PhotoPod: could not read the original of ${item.url}: $e');
    }
  }

  Future<void> _load() async {
    // A slow fetch can finish after the user has already stepped on, so its
    // result is only used if the preview is still showing the same file.

    final item = _item;
    bool current() => mounted && identical(item, _item);

    try {
      final bytes = item.isVideo
          ? await PodMediaService.readBytes(item)
          : await ThumbnailCache.instance.preview(item);
      if (bytes == null) {
        throw const PodMediaException('This photo could not be decoded.');
      }
      if (current()) setState(() => _bytes = bytes);
    } on Object catch (e) {
      if (current()) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),

          // solidui's dark theme caps every dialogue at 500 pixels wide while
          // PhotoPod's light theme does not, so the preview would be wide in
          // one and narrow in the other. It sizes itself from the screen
          // below instead, in both.
          constraints: const BoxConstraints(minWidth: 280),
          child: ConstrainedBox(
            key: widget.contentKey,
            constraints: BoxConstraints(
              maxWidth: media.width * 0.9,
              maxHeight: media.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context),
                const Divider(height: 1),
                Flexible(child: _buildNavigable(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The preview with an arrow either side, when there is more than one file
  /// to step through.
  ///
  /// The arrows sit in their own columns rather than over the picture, so
  /// they never hide part of a photo or cover the video's controls.

  Widget _buildNavigable(BuildContext context) {
    if (widget.items.length < 2) return _buildBody();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildArrow(
          icon: Icons.chevron_left,
          tooltip: 'Previous',
          onPressed: _hasPrevious ? () => _go(-1) : null,
        ),
        Flexible(child: _buildBody()),
        _buildArrow(
          icon: Icons.chevron_right,
          tooltip: 'Next',
          onPressed: _hasNext ? () => _go(1) : null,
        ),
      ],
    );
  }

  Widget _buildArrow({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: IconButton(
      icon: Icon(icon, size: 36),
      tooltip: tooltip,
      onPressed: onPressed,
    ),
  );

  Widget _buildHeader(BuildContext context) {
    final favourites = context.watch<Favourites>();
    final favourite = favourites.contains(_item);
    final actions = widget.actions;
    final item = _item;

    // A photo with a title is headed by it, and its file name moves down
    // among the details; one without is headed by its file name.

    final title = MediaCatalog.titleOf(item.path)?.text;
    final details = [
      if (title != null) item.name,
      if (widget.items.length > 1) '${_index + 1} of ${widget.items.length}',
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

  Future<void> _run(BuildContext context, _HeaderAction action) async {
    final item = _item;
    final actions = widget.actions;
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

    // A title may have been changed in Get Info, or a share made, so the
    // header is drawn again once the action is done.

    if (mounted) setState(() {});
  }

  // Close the preview, then delete what it was showing. The browser asks
  // for confirmation as it does from the toolbar, by which time the preview
  // has gone, so the question is asked over the album rather than over the
  // photo about to be removed.

  void _delete(BuildContext context) {
    final onDelete = widget.actions?.onDelete;
    if (onDelete == null) return;
    final item = _item;
    Navigator.of(context).pop();
    onDelete(item);
  }

  Widget _buildBody() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'This ${_item.kind?.noun ?? 'file'} could not be opened.'
          '\n\n$_error',
          textAlign: TextAlign.center,
        ),
      );
    }

    final bytes = _bytes;
    if (bytes == null) {
      // The grid has almost always fetched the thumbnail already, so it is
      // shown, stretched and softened, while the large rendition comes.

      final thumbnail = ThumbnailCache.instance.cached(_item)?.thumbnail;
      const spinner = Center(child: CircularProgressIndicator());
      if (thumbnail == null) {
        return const Padding(padding: EdgeInsets.all(64), child: spinner);
      }
      return Stack(
        alignment: Alignment.center,
        children: [
          Image.memory(
            thumbnail,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
          spinner,
        ],
      );
    }

    if (_item.isVideo) {
      // No aspect ratio is imposed here: the player sizes its own viewport
      // once the frame size is known, so a portrait clip is shown upright
      // rather than letterboxed into a widescreen box.

      return VideoPreview(
        key: ValueKey(_item.id),
        bytes: bytes,
        fileName: _item.name,
      );
    }

    // The large rendition always sets the size of the picture, so the
    // dialogue does not jump when the original arrives. The original is drawn
    // over it, filling the same box; should it fail to decode, the rendition
    // simply stays visible beneath.

    final original = _original;
    return InteractiveViewer(
      transformationController: _transform,
      maxScale: 8,
      child: Center(
        child: Stack(
          children: [
            Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const Padding(
                padding: EdgeInsets.all(32),
                child: Text('This photo could not be displayed.'),
              ),
            ),
            if (original != null)
              Positioned.fill(
                child: Image.memory(
                  original,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      ),
    );
  }
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
