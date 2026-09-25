/// The picture shown for one item.
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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/thumbnail_cache.dart';

/// The image shown for [item]: the photo itself, a placeholder for a video,
/// or a folder icon.
///
/// Photo thumbnails arrive from the Pod a few requests at a time, so the
/// widget shows a quiet spinner in place of its own tile until the bytes are
/// there, and a broken-image glyph if they never are.

class MediaThumbnail extends StatefulWidget {
  const MediaThumbnail({super.key, required this.item});

  /// The folder or file to picture.

  final MediaItem item;

  @override
  State<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<MediaThumbnail> {
  Future<Uint8List?>? _thumbnail;

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(MediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.url != widget.item.url) _request();
  }

  void _request() {
    _thumbnail = widget.item.isPhoto
        ? ThumbnailCache.instance.thumbnail(widget.item)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (widget.item.isFolder) {
      return _Glyph(icon: Icons.folder, colour: scheme.primary);
    }

    if (widget.item.isVideo) {
      // There is no portable way to pull a frame out of a video without
      // downloading and decoding the whole file, which would make opening a
      // folder of videos very slow. A film glyph says what the item is
      // without that cost, and the preview shows the video itself.

      return _Glyph(icon: Icons.movie, colour: scheme.secondary);
    }

    return FutureBuilder<Uint8List?>(
      future: _thumbnail,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return Center(
            child: snapshot.connectionState == ConnectionState.done
                ? Icon(Icons.broken_image_outlined, color: scheme.outline)
                : SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.outlineVariant,
                    ),
                  ),
          );
        }

        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) =>
              Icon(Icons.broken_image_outlined, color: scheme.outline),
        );
      },
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, required this.colour});

  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) => Center(
    child: LayoutBuilder(
      builder: (context, constraints) => Icon(
        icon,
        size: constraints.biggest.shortestSide * 0.5,
        color: colour,
      ),
    ),
  );
}
