/// A round portrait cut from the photo a face was found in.
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

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:photopod/models/face_book.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/thumbnail_cache.dart';

/// How much room is left around the face, as a multiple of its size, so
/// that the portrait shows the head rather than just the features.

const double _margin = 1.6;

/// [face] shown in a circle: the picture of it kept in the faces file, or,
/// for a face recorded before those were kept, the face cut out of [item]'s
/// grid thumbnail. The box is a fraction of the photo, so it fits the small
/// rendition the grid has usually fetched already.

class FaceAvatar extends StatefulWidget {
  const FaceAvatar({
    super.key,
    required this.face,
    required this.item,
    this.size = 56,
  });

  final FaceRecord face;
  final MediaItem item;
  final double size;

  @override
  State<FaceAvatar> createState() => _FaceAvatarState();
}

class _FaceAvatarState extends State<FaceAvatar> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FaceAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.url != widget.item.url ||
        oldWidget.face.image != widget.face.image) {
      _load();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final own = widget.face.image;
    final bytes = own ?? await ThumbnailCache.instance.thumbnail(widget.item);
    if (bytes == null || !mounted) return;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = frame.image;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = _image;

    return ClipOval(
      child: SizedBox.square(
        dimension: widget.size,
        child: ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: image == null
              ? Icon(
                  Icons.person_outline,
                  color: scheme.outline,
                  size: widget.size * 0.6,
                )
              : CustomPaint(
                  painter: _FacePainter(
                    image,
                    widget.face.image == null
                        ? widget.face.box
                        : const [0, 0, 1, 1],
                  ),
                ),
        ),
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter(this.image, this.box);

  final ui.Image image;
  final List<double> box;

  @override
  void paint(Canvas canvas, Size size) {
    final width = image.width.toDouble();
    final height = image.height.toDouble();

    // A square around the centre of the face, kept inside the picture.

    final centre = Offset(
      (box[0] + box[2] / 2) * width,
      (box[1] + box[3] / 2) * height,
    );
    final side = math.min(
      math.max(box[2] * width, box[3] * height) * _margin,
      math.min(width, height),
    );
    final left = (centre.dx - side / 2).clamp(0.0, width - side);
    final top = (centre.dy - side / 2).clamp(0.0, height - side);

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(left, top, side, side),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_FacePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.box != box;
}
