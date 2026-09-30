/// Grant other WebIDs access to photos, videos and albums.
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

  final webId = await _ownerWebId(context);
  if (webId == null || !context.mounted) return;

  final isFile = folders == 0;
  final noun = isFile ? 'file' : 'folder';

  await showDialog<void>(
    context: context,
    builder: (context) => _ShareDialog(
      title: items.length == 1
          ? 'Share $noun "${items.first.name}"'
          : 'Share ${items.length} ${noun}s',
      ownerWebId: webId,
      isFile: isFile,
      resourceUrls: [for (final item in items) item.url],
      displayName: items.length == 1 ? items.first.name : null,
    ),
  );
}

/// Share the album called [albumName], holding [itemCount] photos and
/// videos, with other Solid users.
///
/// What the dialogue shares is the album file at [albumFileUrl], so the album
/// file's access list is the one record of who the album is shared with.
/// Once the dialogue closes the caller brings the photos and videos in the
/// album into line with it — see `AlbumSharing` — which is also what keeps
/// anything added to the album later shared, and what takes a photo back
/// from a recipient only when no other shared album still holds it.

Future<void> showAlbumShareDialog(
  BuildContext context, {
  required String albumName,
  required String albumFileUrl,
  required int itemCount,
}) async {
  final webId = await _ownerWebId(context);
  if (webId == null || !context.mounted) return;

  final what = itemCount == 1
      ? 'the one photo or video in it'
      : 'all $itemCount photos and videos in it';

  await showDialog<void>(
    context: context,
    builder: (context) => _ShareDialog(
      title: 'Share album "$albumName"',
      ownerWebId: webId,
      isFile: true,
      resourceUrls: [albumFileUrl],
      displayName: 'the album "$albumName"',
      titles: {albumFileUrl: 'Album: $albumName'},
      note:
          'Sharing "$albumName" also shares ${itemCount == 0 ? 'every photo '
                    'and video you put into it' : what}, including anything '
          'added later. Removing someone here takes the photos away from '
          'them too, except those still in another album shared with them '
          'or shared with them directly.',
    ),
  );
}

/// The logged-in user's WebID, or null, after telling the user why, when
/// there is none to share as.

Future<String?> _ownerWebId(BuildContext context) async {
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
    return null;
  }

  if (webId == null && context.mounted) {
    await showErrorDialog(
      context,
      'Cannot share',
      'You need to be logged in to your Pod before sharing.',
    );
  }
  return webId;
}

class _ShareDialog extends StatelessWidget {
  const _ShareDialog({
    required this.title,
    required this.ownerWebId,
    required this.isFile,
    required this.resourceUrls,
    this.displayName,
    this.titles,
    this.note,
  });

  final String title;
  final String ownerWebId;
  final bool isFile;
  final List<String> resourceUrls;

  /// The name the recipient's notification uses for what was shared.

  final String? displayName;

  /// Friendly names for [resourceUrls], shown in place of the bare URLs.

  final Map<String, String>? titles;

  /// A line of explanation shown above the permission view.

  final String? note;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final theme = Theme.of(context);

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
                    child: Text(title, style: theme.textTheme.titleMedium),
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
            if (note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(note!, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: GrantPermissionUi(
                showAppBar: false,
                isFile: isFile,
                ownerWebId: ownerWebId,
                resourceNames: resourceUrls,
                resourceDisplayName: displayName,
                titleData: titles,
                inviteConfig: inviteOthersConfig,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
