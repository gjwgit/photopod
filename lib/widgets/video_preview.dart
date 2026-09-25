/// Play a video held in the Pod.
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

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:photopod/constants/media.dart';

/// Play [bytes], a video already fetched from the Pod.
///
/// The bytes are handed to media_kit rather than the resource URL because
/// every read from a Solid server needs a DPoP header that a player cannot
/// attach for itself. [Media.memory] then does the right thing per platform:
/// a temporary file on desktop and mobile, an object URL on the web, cleaned
/// up when the media is collected.

class VideoPreview extends StatefulWidget {
  const VideoPreview({super.key, required this.bytes, required this.fileName});

  /// The video file's contents.

  final Uint8List bytes;

  /// The name the file has on the Pod, used to tell the player what sort of
  /// video it has been handed.

  final String fileName;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<VideoParams>? _params;
  double? _aspectRatio;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    // The player and its video output have to exist BEFORE the media is
    // opened. A `late final` field is only built when it is first read, so
    // creating the controller lazily in `build` attached the video output to
    // a player that had already begun decoding: the sound played and the
    // picture never appeared. Creating both here, eagerly and in order, is
    // what markdown_widget_builder does too.

    _player = Player();
    _controller = VideoController(_player);

    // The real frame size only becomes known once decoding starts, so the
    // viewport follows it rather than assuming every clip is widescreen. A
    // portrait video from a phone would otherwise be a sliver in a 16:9 box.

    _params = _player.stream.videoParams.listen((params) {
      final width = params.dw ?? params.w;
      final height = params.dh ?? params.h;
      if (width == null || height == null || width <= 0 || height <= 0) return;
      final ratio = width / height;
      if (mounted && ratio != _aspectRatio) {
        setState(() => _aspectRatio = ratio);
      }
    });

    _open();
  }

  Future<void> _open() async {
    try {
      final media = await Media.memory(
        widget.bytes,
        type: contentTypeOf(widget.fileName),
      );
      await _player.open(media);
      if (mounted) setState(() => _ready = true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _params?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The viewport keeps its shape through loading, playback and failure, so
    // the dialogue does not jump about as the video becomes ready.

    return AspectRatio(
      aspectRatio: _aspectRatio ?? 16 / 9,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This video could not be played.\n\n$error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    return Video(controller: _controller, controls: AdaptiveVideoControls);
  }
}
