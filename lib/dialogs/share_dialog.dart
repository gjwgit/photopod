/// Grant other WebIDs access to photos and videos.
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

import 'package:flutter/material.dart';

import 'package:solidpod/solidpod.dart' show getWebId;
import 'package:solidui/solidui.dart' show GrantPermissionUi;

import 'package:photopod/constants/app.dart';
import 'package:photopod/dialogs/message_dialog.dart';
import 'package:photopod/models/media_item.dart';

/// Share [items] with other Solid users.
///
/// Sharing is Solid's own mechanism rather than anything PhotoPod invents:
/// the dialogue hosts SolidUI's grant permission view, the same one NotePod
/// uses, which writes the access control list for each resource and can send
/// the recipient a notification. Items are addressed by their full resource
/// URL, so a photo shared from PhotoPod can be opened by any Solid client.
///
/// A permission applies to a resource either as a file or as a container, so
/// a selection that mixes the two is reported rather than half shared.

Future<void> showShareDialog(
  BuildContext context,
  List<MediaItem> items,
) async {
  if (items.isEmpty) return;

  final folders = items.where((item) => item.isFolder).length;
  if (folders != 0 && folders != items.length) {
    await showErrorDialog(
      context,
      'Cannot share this selection',
      'Files and folders are shared separately on a Solid Pod. Please select '
          'either files or folders, and share them in two steps.',
    );
    return;
  }

  final String? webId;
  try {
    webId = await getWebId();
  } on Object catch (e) {
    if (context.mounted) {
      await showErrorDialog(
        context,
        'Cannot share',
        'Your WebID could not be read from the Pod.\n\n$e',
      );
    }
    return;
  }

  if (webId == null) {
    if (context.mounted) {
      await showErrorDialog(
        context,
        'Cannot share',
        'You need to be logged in to your Pod before sharing.',
      );
    }
    return;
  }

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (context) =>
        _ShareDialog(items: items, ownerWebId: webId!, isFile: folders == 0),
  );
}

class _ShareDialog extends StatelessWidget {
  const _ShareDialog({
    required this.items,
    required this.ownerWebId,
    required this.isFile,
  });

  final List<MediaItem> items;
  final String ownerWebId;
  final bool isFile;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final noun = isFile ? 'file' : 'folder';
    final title = items.length == 1
        ? 'Share $noun "${items.first.name}"'
        : 'Share ${items.length} ${noun}s';

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 900,
          maxHeight: size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: GrantPermissionUi(
                showAppBar: false,
                isFile: isFile,
                ownerWebId: ownerWebId,
                resourceNames: [for (final item in items) item.url],
                resourceDisplayName: items.length == 1
                    ? items.first.name
                    : null,
                inviteConfig: inviteOthersConfig,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
