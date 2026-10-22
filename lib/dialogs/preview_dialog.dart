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

import 'package:photopod/constants/media.dart';
import 'package:photopod/dialogs/download_media.dart';
import 'package:photopod/dialogs/info_dialog.dart';
import 'package:photopod/models/favourites.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/pod_media_service.dart';
import 'package:photopod/services/thumbnail_cache.dart';
import 'package:photopod/utils/formatting.dart';
import 'package:photopod/widgets/media_thumbnail.dart';
import 'package:photopod/widgets/video_preview.dart';

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
      ),
    ),
  );
}

/// The preview's route: an ordinary dialogue route whose opening transition
/// grows the dialogue from [origin], the rectangle of the tile that was
/// opened, to its full size. Without an origin it opens as any dialogue does.

class _PreviewRoute extends DialogRoute<void> {
  _PreviewRoute({
    required super.context,
    required super.builder,
    required this.origin,
    required this.contentKey,
    super.themes,
    super.barrierColor,
  });

  final Rect? origin;

  /// Marks the dialogue's panel, whose laid out rectangle is where the
  /// growth ends.

  final GlobalKey contentKey;

  static const _grow = Duration(milliseconds: 300);

  @override
  Duration get transitionDuration =>
      origin == null ? super.transitionDuration : _grow;

  @override
  Duration get reverseTransitionDuration =>
      origin == null ? super.reverseTransitionDuration : _fadeOut;

  static const _fadeOut = Duration(milliseconds: 150);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final origin = this.origin;
    if (origin == null) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }

    // The same widgets are built while opening and closing, so that the
    // dialogue keeps its state. Closing only fades: by then the user may
    // have stepped to a file whose tile is elsewhere, or off screen.

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final closing = animation.status == AnimationStatus.reverse;
        final value = animation.value;
        return _GrowFrom(
          origin: origin,
          target: contentKey,
          progress: closing ? 1 : Curves.easeOutCubic.transform(value),
          child: Opacity(
            opacity: closing ? value : const Interval(0, 0.35).transform(value),
            child: child,
          ),
        );
      },
    );
  }
}

/// Paints its child scaled and moved so that the panel marked by [target]
/// starts within [origin] and, as [progress] runs from 0 to 1, grows to
/// where it was laid out.
///
/// The panel keeps its own shape throughout, starting as large as fits in
/// the tile, so the photo and the header are never stretched. Layout is
/// untouched: only painting is transformed.

class _GrowFrom extends SingleChildRenderObjectWidget {
  const _GrowFrom({
    required this.origin,
    required this.target,
    required this.progress,
    super.child,
  });

  /// Where the growth starts, in global coordinates.

  final Rect origin;

  final GlobalKey target;

  final double progress;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGrowFrom(origin: origin, target: target, progress: progress);

  @override
  void updateRenderObject(BuildContext context, _RenderGrowFrom renderObject) {
    renderObject
      ..origin = origin
      ..target = target
      ..progress = progress;
  }
}

class _RenderGrowFrom extends RenderProxyBox {
  _RenderGrowFrom({
    required Rect origin,
    required GlobalKey target,
    required double progress,
  }) : _origin = origin,
       _target = target,
       _progress = progress;

  Rect _origin;
  set origin(Rect value) {
    if (value == _origin) return;
    _origin = value;
    markNeedsPaint();
  }

  GlobalKey _target;
  set target(GlobalKey value) {
    if (value == _target) return;
    _target = value;
    markNeedsPaint();
  }

  double _progress;
  set progress(double value) {
    if (value == _progress) return;
    _progress = value;
    markNeedsPaint();
  }

  // The panel is found when painting, after it has been laid out, so the
  // growth always ends exactly where the dialogue sits.

  Matrix4? _transform() {
    if (_progress >= 1) return null;
    final box = _target.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return null;

    final end = MatrixUtils.transformRect(
      box.getTransformTo(this),
      Offset.zero & box.size,
    );
    final start = globalToLocal(_origin.topLeft) & _origin.size;
    final first = min(start.width / end.width, start.height / end.height);

    final scale = lerpDouble(first, 1, _progress)!;
    final centre = Offset.lerp(start.center, end.center, _progress)!;
    return Matrix4.translationValues(centre.dx, centre.dy, 0)
      ..multiply(Matrix4.diagonal3Values(scale, scale, 1))
      ..multiply(Matrix4.translationValues(-end.center.dx, -end.center.dy, 0));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final transform = _transform();
    if (transform == null) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }
}

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({
    required this.items,
    required this.initialIndex,
    required this.contentKey,
  });

  /// The files the arrows step through, in display order.

  final List<MediaItem> items;

  /// Where in [items] the preview starts.

  final int initialIndex;

  /// Marks the panel the opening transition grows.

  final GlobalKey contentKey;

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

    final details = [
      if (widget.items.length > 1) '${_index + 1} of ${widget.items.length}',
      if (_item.size != null) formatBytes(_item.size),
      if (_item.modified != null) formatDateTime(_item.modified),
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: Row(
        children: [
          Icon(
            _item.isVideo ? Icons.movie : Icons.image,
            color: Theme.of(context).colorScheme.primary,
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _item.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (details.isNotEmpty)
                  Text(details, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              favourite ? Icons.favorite : Icons.favorite_border,
              color: favourite ? const Color(0xFFE53935) : null,
            ),
            tooltip: favourite ? 'Remove from Favourites' : 'Add to Favourites',
            onPressed: () => favourites.toggleAll([_item]),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download the original',
            onPressed: () => downloadMedia(context, [_item]),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Get Info',
            onPressed: () => showInfoDialog(context, _item),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
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
