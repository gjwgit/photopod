/// Share a copy of a photo or video with other applications.
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

import 'package:flutter/foundation.dart'
    show TargetPlatform, Uint8List, compute, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:share_plus/share_plus.dart';

import 'package:photopod/constants/media.dart';
import 'package:photopod/dialogs/download_media.dart';
import 'package:photopod/dialogs/message_dialog.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/share_route.dart';
import 'package:photopod/services/pod_media_service.dart';
import 'package:photopod/services/thumbnail_cache.dart';

export 'package:photopod/models/share_route.dart';

/// Send a copy of [items] to another application by [route]: the platform's
/// share sheet, or the clipboard.
///
/// [origin] is the rectangle, in global coordinates, of the button pressed.
/// The iPad and macOS anchor the share sheet's popover to it.

Future<void> shareCopies(
  BuildContext context,
  List<MediaItem> items,
  ShareRoute route, {
  Rect? origin,
}) => switch (route) {
  ShareRoute.sheet => shareMedia(context, items, origin: origin),
  ShareRoute.copy => copyMediaToClipboard(context, items),
};

/// Hand a copy of the originals of [items] to the platform's share sheet.

Future<void> shareMedia(
  BuildContext context,
  List<MediaItem> items, {
  Rect? origin,
}) async {
  final read = await _fetch(context, items, 'Preparing');
  if (read == null || read.isEmpty || !context.mounted) return;

  final subject = _subjectOf(read);
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          for (final file in read)
            XFile.fromData(file.bytes, mimeType: contentTypeOf(file.name)),
        ],

        // The name given to XFile.fromData is ignored on most platforms, so
        // without this the recipient would see a random one.
        fileNameOverrides: [for (final file in read) file.name],
        title: read.length == 1 ? read.single.name : null,
        sharePositionOrigin: origin,

        // A browser without the Web Share API would otherwise download the
        // files, which the Download button already does, and which would
        // look as though sharing had worked.
        downloadFallbackEnabled: false,
      ),
    );
  } on Object catch (e) {
    debugPrint('PhotoPod: could not share $subject: $e');
    if (!context.mounted) return;
    final canCopy = shareRoutesFor(items).contains(ShareRoute.copy);
    await showErrorDialog(
      context,
      'Could not share $subject',
      'This ${kIsWeb ? 'browser' : 'device'} could not open its share sheet '
          'for ${read.length == 1 ? 'this file' : 'these files'}.'
          '${canCopy ? ' Use Copy instead, and paste where you want.' : ''}'
          ' Download saves a copy you can then share from elsewhere.',
    );
  }
}

/// Put a copy of [items] on the clipboard, ready to paste into another
/// application.
///
/// A single photo goes on as an image wherever the platform lets PhotoPod
/// put one there: that is what Signal, WhatsApp, Teams and the like accept
/// when pasted into. Otherwise, as for a video or for several files at once,
/// the originals are saved to a temporary folder and the files themselves go
/// on the clipboard, as a file manager would place them, ready to paste as
/// attachments.

Future<void> copyMediaToClipboard(
  BuildContext context,
  List<MediaItem> items,
) async {
  final read = await _fetch(context, items, 'Copying');
  if (read == null || read.isEmpty || !context.mounted) return;

  final subject = _subjectOf(read);
  final asImage =
      read.length == 1 && !read.single.item.isVideo && _imagesOnClipboard;
  try {
    await showWorking(context, 'Copying $subject...', () async {
      if (asImage) {
        final file = read.single;
        await Pasteboard.writeImage(await _asPng(file.item, file.bytes));
      } else {
        await _copyAsFiles(read);
      }
    });
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Copied $subject. Paste into any app.')),
    );
  } on Object catch (e) {
    if (context.mounted) {
      await showErrorDialog(context, 'Could not copy $subject', '$e');
    }
  }
}

// One original read from the Pod, under the name it goes out by.

typedef _Read = ({MediaItem item, String name, Uint8List bytes});

String _subjectOf(List<_Read> read) =>
    read.length == 1 ? '"${read.single.name}"' : '${read.length} files';

// The pasteboard package writes an image to the clipboard on macOS, Windows
// and the web. On Linux it quietly does nothing, so there the file is copied
// instead.

bool get _imagesOnClipboard =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows;

// Read the originals of the photos and videos among [items], asking for the
// security key first if any is encrypted, behind a spinner. Null when the
// user gave no key or a read failed, which has then been reported.

Future<List<_Read>?> _fetch(
  BuildContext context,
  List<MediaItem> items,
  String verb,
) async {
  final files = shareableFiles(items);
  if (files.isEmpty) return const [];
  if (!await unlockToRead(
    context,
    files,
    'Please enter your security key to share your files',
  )) {
    return null;
  }
  if (!context.mounted) return null;

  final read = <_Read>[];
  for (final item in files) {
    if (!context.mounted) return null;
    final progress = files.length == 1
        ? '"${item.name}"'
        : '${read.length + 1} of ${files.length}';
    try {
      final media = await showWorking(
        context,
        '$verb $progress...',
        () => PodMediaService.readMedia(item),
      );
      read.add((
        item: item,
        name: knownNameOf(item, media),
        bytes: media.bytes,
      ));
    } on Object catch (e) {
      if (context.mounted) {
        await showErrorDialog(context, 'Could not read "${item.name}"', '$e');
      }
      return null;
    }
  }
  return read;
}

// The photo as a PNG, the one image format every clipboard takes: a browser
// accepts nothing else, and a JPEG handed to Windows or macOS as it stands
// can lose its rotation. A photo that will not decode here, a HEIC on
// Windows say, falls back to its large rendition, which always does.

Future<Uint8List> _asPng(MediaItem item, Uint8List original) async {
  final png = await compute(convertToPng, original);
  if (png != null) return png;
  final preview = await ThumbnailCache.instance.preview(item);
  final fallback = preview == null
      ? null
      : await compute(convertToPng, preview);
  if (fallback == null) {
    throw const PodMediaException('This photo could not be decoded.');
  }
  return fallback;
}

// Save each of [read] under its name in the temporary folder and place those
// files on the clipboard. A later copy of a file of the same name replaces
// it, so the folder does not fill up with them; the system clears the rest
// in time.

Future<void> _copyAsFiles(List<_Read> read) async {
  final folder = await getTemporaryDirectory();
  final separator = defaultTargetPlatform == TargetPlatform.windows
      ? r'\'
      : '/';
  final paths = <String>[];
  for (final file in read) {
    final path = '${folder.path}$separator${file.name}';
    await XFile.fromData(file.bytes).saveTo(path);
    paths.add(path);
  }
  if (!await Pasteboard.writeFiles(paths)) {
    throw const PodMediaException(
      'The clipboard on this device did not accept the files.',
    );
  }
}
