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

/// The opening frame of [bytes], a video called [fileName], as a JPEG scaled
/// to the grid's thumbnail size, or null when no frame could be read.
///
/// The video is opened, paused, in a player that is never shown. The player
/// is given a video output because without one media_kit does not decode the
/// picture at all, and so has nothing to take a screenshot of. The frame then
/// goes through the same downscaling as a photo, so that what is stored is
/// small however large the video is.

Future<Uint8List?> firstFrameThumbnail(Uint8List bytes, String fileName) async {
  final player = Player();
  final controller = VideoController(player);

  try {
    await player.setVolume(0);
    final media = await Media.memory(bytes, type: contentTypeOf(fileName));
    await player.open(media, play: false);
    await controller.waitUntilFirstFrameRendered.timeout(_firstFrameTimeout);

    final frame = await player.screenshot(format: 'image/jpeg');
    if (frame == null || frame.isEmpty) return null;

    return (await compute(analysePhoto, frame))?.thumbnail;
  } on Object catch (e) {
    debugPrint('PhotoPod: could not capture a frame of $fileName: $e');
    return null;
  } finally {
    await player.dispose();
  }
}
