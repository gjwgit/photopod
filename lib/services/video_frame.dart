/// Capture the opening frame of a video as a thumbnail.
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

import 'package:flutter/foundation.dart';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:photopod/constants/media.dart';
import 'package:photopod/services/thumbnail_cache.dart';

/// How long to wait for the opening frame to be decoded before giving up on
/// it. A video the player cannot decode never produces one, and adding it to
/// the Pod should not hang because of that.

const Duration _firstFrameTimeout = Duration(seconds: 15);

/// How often to ask the headless
/// player for its frame while waiting for the
/// first one to be decoded.

const Duration _framePollInterval = Duration(milliseconds: 100);

/// The opening frame of [bytes], a video called [fileName], as a JPEG scaled
/// to the grid's thumbnail size, or null when no frame could be read.
///
/// The video is opened, paused, in a player that is never shown. The frame
/// then goes through the same downscaling as a photo, so that what is stored
/// is small however large the video is.

Future<Uint8List?> firstFrameThumbnail(Uint8List bytes, String fileName) {
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.linux
      ? _headlessFirstFrame(bytes, fileName)
      : _rendererFirstFrame(bytes, fileName);
}

/// Capture through a [VideoController], as the preview dialogue plays.
///
/// The player is given a video output because without one media_kit does not
/// decode the picture at all, and so has nothing to take a screenshot of.

Future<Uint8List?> _rendererFirstFrame(Uint8List bytes, String fileName) async {
  final player = Player();
  final controller = VideoController(player);

  try {
    await player.setVolume(0);
    final media = await Media.memory(bytes, type: contentTypeOf(fileName));
    await player.open(media, play: false);
    await controller.waitUntilFirstFrameRendered.timeout(_firstFrameTimeout);

    final frame = await player.screenshot(format: 'image/jpeg');
    return await _toThumbnail(frame);
  } on Object catch (e) {
    debugPrint('PhotoPod: could not capture a frame of $fileName: $e');
    return null;
  } finally {
    await player.dispose();
  }
}

/// Capture on Linux, where a [VideoController] cannot be used off screen.
///
/// media_kit_video on Linux draws each frame only when Flutter paints the
/// video's texture, which happens only while a Video widget is mounted. A
/// player that is never shown therefore never draws anything: its "first
/// frame rendered" signal fires straight away for a 1x1 placeholder, and the
/// screenshot that follows comes back empty.
///
/// Instead the player is given mpv's null video output, with video decoding
/// switched back on (media_kit turns it off unless a controller is
/// attached). The null output keeps the last decoded frame, which is what a
/// screenshot falls back to, so the frame is read without anything being
/// drawn. Audio is not decoded at all.

Future<Uint8List?> _headlessFirstFrame(Uint8List bytes, String fileName) async {
  final player = Player(
    configuration: const PlayerConfiguration(vo: 'null', muted: true),
  );

  try {
    final native = player.platform as NativePlayer;
    await native.setProperty('vid', 'auto');
    await native.setProperty('aid', 'no');

    final media = await Media.memory(bytes, type: contentTypeOf(fileName));
    await player.open(media, play: false);

    // Paused at the start, mpv still decodes and hands over the opening
    // frame, but a moment after the file is opened rather than at once, so
    // the screenshot is retried until that frame has arrived.

    final deadline = DateTime.now().add(_firstFrameTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final frame = await player.screenshot(format: 'image/jpeg');
      if (frame != null && frame.isNotEmpty) return await _toThumbnail(frame);
      await Future<void>.delayed(_framePollInterval);
    }

    debugPrint('PhotoPod: no frame of $fileName was decoded in time');
    return null;
  } on Object catch (e) {
    debugPrint('PhotoPod: could not capture a frame of $fileName: $e');
    return null;
  } finally {
    await player.dispose();
  }
}

/// Downscale a captured [frame] to the grid's thumbnail size.

Future<Uint8List?> _toThumbnail(Uint8List? frame) async {
  if (frame == null || frame.isEmpty) return null;
  return (await compute(analysePhoto, frame))?.thumbnail;
}
