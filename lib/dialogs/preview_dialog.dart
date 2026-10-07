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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gap/gap.dart';
import 'package:provider/provider.dart';

import 'package:photopod/constants/media.dart';
import 'package:photopod/dialogs/info_dialog.dart';
import 'package:photopod/models/favourites.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/pod_media_service.dart';
import 'package:photopod/services/thumbnail_cache.dart';
import 'package:photopod/utils/formatting.dart';
import 'package:photopod/widgets/video_preview.dart';

/// Preview [item] in a modal dialogue.
///
/// Photos can be pinched or scrolled to zoom; videos get playback controls.
/// The file is fetched at full size here rather than reusing the grid's
/// thumbnail, so what the user sees is the photo as it is actually stored.
///
/// When [items] is given, arrows either side of the preview (and the left and
/// right arrow keys) step to the previous and next photo or video in it.
/// Folders and files PhotoPod cannot show are skipped.

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

  return showDialog<void>(
    context: context,
    builder: (context) => _PreviewDialog(items: playable, initialIndex: index),
  );
}

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.items, required this.initialIndex});

  /// The files the arrows step through, in display order.

  final List<MediaItem> items;

  /// Where in [items] the preview starts.

  final int initialIndex;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  late int _index;
  Uint8List? _bytes;
  String? _error;

  MediaItem get _item => widget.items[_index];

  bool get _hasPrevious => _index > 0;

  bool get _hasNext => _index < widget.items.length - 1;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _load();
  }

  /// Move [step] places through the list and fetch the file found there.

  void _go(int step) {
    final next = _index + step;
    if (next < 0 || next >= widget.items.length) return;
    setState(() {
      _index = next;
      _bytes = null;
      _error = null;
    });
    _load();
  }

  Future<void> _load() async {
    // A slow fetch can finish after the user has already stepped on, so its
    // result is only used if the preview is still showing the same file.

    final item = _item;
    bool current() => mounted && identical(item, _item);

    try {
      var bytes = await PodMediaService.readBytes(item);

      // TIFF has no Flutter codec, so those photos are re-encoded as PNG on a
      // background isolate before they can be shown.

      if (isTiff(item.name)) {
        final png = await compute(convertToPng, bytes);
        if (png == null) {
          throw const PodMediaException('This TIFF file could not be decoded.');
        }
        bytes = png;
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
      return const Padding(
        padding: EdgeInsets.all(64),
        child: Center(child: CircularProgressIndicator()),
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

    return InteractiveViewer(
      maxScale: 8,
      child: Center(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => const Padding(
            padding: EdgeInsets.all(32),
            child: Text('This photo could not be displayed.'),
          ),
        ),
      ),
    );
  }
}
