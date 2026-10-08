/// Save the originals of photos and videos from the Pod onto this device.
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

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import 'package:solidpod/solidpod.dart' show KeyManager;
import 'package:solidui/solidui.dart' show getKeyFromUserIfRequired;

import 'package:photopod/constants/media.dart';
import 'package:photopod/dialogs/message_dialog.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/pod_keys.dart';
import 'package:photopod/services/pod_media_service.dart';

/// Download the original of each of [items], asking where to save each one.
///
/// This is the one place PhotoPod fetches a photo at full size: the grid and
/// the preview show the smaller renditions kept beside it. Each file is
/// fetched and decrypted first, behind a progress dialogue, and then the save
/// dialogue offers its own name. Cancelling a save stops the rest. Folders
/// are passed over.

Future<void> downloadMedia(BuildContext context, List<MediaItem> items) async {
  final files = items.where((item) => !item.isFolder).toList();
  if (files.isEmpty) return;

  if (files.any((item) => item.isEncrypted)) {
    await getKeyFromUserIfRequired(
      context,
      const Text('Please enter your security key to download your files'),
    );
    if (!await KeyManager.hasSecurityKey()) return;
    await PodKeys.prime();
  }

  for (final item in files) {
    if (!context.mounted) return;
    try {
      final bytes = await showWorking(
        context,
        'Downloading "${item.name}"...',
        () => PodMediaService.readBytes(item),
      );
      final saved = await FilePicker.saveFile(
        fileName: item.name,
        bytes: bytes,
        mimeType: contentTypeOf(item.name),
        dialogTitle: 'Save "${item.name}"',
      );

      // The browser saves a download without saying where, so on the web
      // there is no cancelled save to stop at.

      if (saved == null && !kIsWeb) return;
    } on Object catch (e) {
      if (context.mounted) {
        await showErrorDialog(
          context,
          'Could not download "${item.name}"',
          '$e',
        );
      }
      return;
    }
  }
}
