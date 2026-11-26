/// The routes by which a copy of a photo or video can go to another app.
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
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart' show IconData, Icons;

import 'package:photopod/models/media_item.dart';

// This is ordinary sharing: a copy of the original leaves the Pod for another
// application, such as Signal, WhatsApp, Teams or email, and from then on is
// out of the owner's hands. It is quite separate from sharing on the Pod (see
// share_dialog.dart), which gives other Solid users access by WebID to items
// that stay where they are, and which therefore has an icon of its own.

/// The ways a copy of a photo or video can leave PhotoPod.

enum ShareRoute {
  /// The platform's own share sheet, listing the applications installed.

  sheet,

  /// The clipboard, to be pasted into another application.
  copy,
}

/// The photos and videos among [items] that can be shared as a copy. Folders,
/// and files PhotoPod does not recognise, are passed over.

List<MediaItem> shareableFiles(List<MediaItem> items) => [
  for (final item in items)
    if (!item.isFolder && item.kind != null) item,
];

/// The routes open to [items] on this platform, most useful first.
///
/// - Android and iOS: the share sheet alone. It already lists the messaging
///   apps, and offers its own Copy.
/// - macOS and Windows: the share sheet, and the clipboard, since pasting is
///   how most people move a picture into a desktop application.
/// - The web: the browser's share sheet, where it has one, and the clipboard
///   for a single photo. A browser puts one image on the clipboard, and
///   never a video or a file.
/// - Linux: the clipboard alone, as there is no share sheet to call on.
///
/// One photo goes on the clipboard as an image, ready to paste into a chat.
/// Anything else goes on as files, which only the desktop can do.

List<ShareRoute> shareRoutesFor(List<MediaItem> items) {
  final files = shareableFiles(items);
  if (files.isEmpty) return const [];
  final onePhoto = files.length == 1 && !files.single.isVideo;
  if (kIsWeb) return [ShareRoute.sheet, if (onePhoto) ShareRoute.copy];
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => const [ShareRoute.sheet],
    TargetPlatform.macOS ||
    TargetPlatform.windows => const [ShareRoute.sheet, ShareRoute.copy],
    TargetPlatform.linux => const [ShareRoute.copy],
  };
}

/// The icon a menu shows for [route]. The share sheet wears the platform's
/// own share icon: the three linked dots on Android, Windows and Linux, the
/// box and arrow on iOS and macOS.

IconData shareRouteIcon(ShareRoute route) => switch (route) {
  ShareRoute.sheet => Icons.adaptive.share,
  ShareRoute.copy => Icons.copy_outlined,
};

/// What a menu calls [route].

String shareRouteLabel(ShareRoute route) => switch (route) {
  ShareRoute.sheet => 'Share...',
  ShareRoute.copy => 'Copy',
};
