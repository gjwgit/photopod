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

Future<void> showPreviewDialog(BuildContext context, MediaItem item) =>
    showDialog<void>(
      context: context,
      builder: (context) => _PreviewDialog(item: item),
    );

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.item});

  final MediaItem item;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var bytes = await PodMediaService.readBytes(widget.item);

      // TIFF has no Flutter codec, so those photos are re-encoded as PNG on a
      // background isolate before they can be shown.

      if (isTiff(widget.item.name)) {
        final png = await compute(convertToPng, bytes);
        if (png == null) {
          throw const PodMediaException('This TIFF file could not be decoded.');
        }
        bytes = png;
      }

      if (mounted) setState(() => _bytes = bytes);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
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
            Flexible(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final favourites = context.watch<Favourites>();
    final favourite = favourites.contains(widget.item);

    final details = [
      if (widget.item.size != null) formatBytes(widget.item.size),
      if (widget.item.modified != null) formatDateTime(widget.item.modified),
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: Row(
        children: [
          Icon(
            widget.item.isVideo ? Icons.movie : Icons.image,
            color: Theme.of(context).colorScheme.primary,
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.name,
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
            onPressed: () => favourites.toggleAll([widget.item]),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Get Info',
            onPressed: () => showInfoDialog(context, widget.item),
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
          'This ${widget.item.kind?.noun ?? 'file'} could not be opened.'
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

    if (widget.item.isVideo) {
      // No aspect ratio is imposed here: the player sizes its own viewport
      // once the frame size is known, so a portrait clip is shown upright
      // rather than letterboxed into a widescreen box.

      return VideoPreview(bytes: bytes, fileName: widget.item.name);
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
