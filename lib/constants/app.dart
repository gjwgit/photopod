/// PhotoPod - app-wide constants.
///
// Time-stamp: <Sunday 2026-08-30 14:14:09 +1000 Graham Williams>
///
/// Copyright (C) 2026, Togaware Pty Ltd
///
/// Licensed under the GNU General Public License, Version 3 (the "License");
///
/// License: https://opensource.org/license/gpl-3-0
//
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
// this program.  If not, see <https://opensource.org/license/gpl-3-0>.
///
/// Authors: Graham Williams

library;

import 'package:flutter/material.dart';

/// Application name displayed in the UI.

const appName = 'PhotoPod';

/// Application title displayed as the window title.

const String appTitle = 'PhotoPod - Manage Your Photos';

/// App directory name used by solidpod for storage paths.

const appDirectory = 'photopod';

/// Pod sub-directory holding the encrypted full-size photos.

const photosDirName = 'photos';

/// Pod sub-directory holding the encrypted thumbnails.
///
/// Thumbnails live in their own directory rather than beside the originals so
/// the gallery can be painted from a small, cheap directory while the
/// full-size photos are only ever fetched one at a time on tap.

const thumbsDirName = 'thumbs';

/// Pod filename for the photo metadata index, held inside [photosDirName] so
/// it inherits that directory's encryption key.
///
/// The content is JSON, but the extension must be `.ttl`: solidpod refuses to
/// write an encrypted resource whose name does not end in `.ttl`, and the
/// index lists filenames and captions, so it is encrypted like everything
/// else. Because it is encrypted the stored bytes are ciphertext anyway —
/// `readPod` hands back the JSON string unchanged, with no Turtle to parse.

const photoIndexFileName = 'photo_index.ttl';

/// Suffix given to an encrypted photo or thumbnail resource.
///
/// The `.enc` marks it as ciphertext at a glance in a file browser, and the
/// trailing `.ttl` satisfies solidpod's requirement that encrypted resources
/// carry a Turtle extension.

const encryptedSuffix = '.enc.ttl';

/// Longest edge, in pixels, of a generated thumbnail.
///
/// Large enough to stay crisp on a high-density grid tile, small enough that
/// a whole gallery of them decrypts in well under a second.

const thumbnailMaxEdge = 320;

/// JPEG quality used when encoding a thumbnail.

const thumbnailQuality = 80;

/// File extensions accepted when picking photos to upload.

const photoExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'];

/// Largest photo, in bytes, accepted for upload.
///
/// Encrypted photos are base64-encoded into a Turtle literal, so the stored
/// resource is roughly a third larger again than the original. This ceiling
/// keeps a single write within what a Solid server will comfortably accept.

const maxPhotoBytes = 20 * 1024 * 1024;

/// Extent of a gallery grid tile in logical pixels.

const galleryTileExtent = 160.0;

/// Spacing between gallery grid tiles.

const galleryTileSpacing = 8.0;

/// SnackBar colours.
///
/// Deliberately understated: a soft pastel BAR carrying near-black text,
/// rather than a saturated theme colour. Tune these to restyle every
/// SnackBar. A negative/orange bar colour goes here when one is first needed.

const snackBarPositive = Color(0xFFC8E6C9); // green.shade100 — bar colour
const snackBarInk = Color(0xFF1B1B1B); // near-black text on a pastel bar

/// How long a SnackBar stays on screen.
///
/// One standard time for every message, matching Flutter's own default.
/// Do NOT extend it for an Undo action — the button rides along for the
/// standard time and then the bar gets out of the way.

const snackBarDuration = Duration(seconds: 4);

/// Surface and text for a SnackBar with no positive or negative sense, e.g.
/// one built directly rather than through app_snack_bar.dart.

const snackBarSurface = Color(0xFF212121); // grey.shade900
const snackBarNeutral = Color(0xFFE0E0E0); // grey.shade300
