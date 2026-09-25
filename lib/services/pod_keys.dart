/// Getting solidpod's keys into memory before anything asks for them at once.
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

import 'package:flutter/foundation.dart';

import 'package:solidpod/solidpod.dart'
    show KeyManager, getDataDirPath, getDirUrl;

/// Read solidpod's key material once, before PhotoPod starts asking for it
/// from several places at the same time.
///
/// solidpod holds the per-resource encryption keys in a single static map,
/// which it fills from the Pod the first time any key is wanted, and derives
/// the master key on first use as well. Neither is guarded against being
/// asked for twice at once, and PhotoPod asks for a great deal at once: a
/// page of thumbnails is four concurrent reads, the album index walks every
/// folder, and the map reads every photo in turn.
///
/// Two requests that both arrive before the key map has been read each start
/// their own read, and the slower of the two replaces the map with what the
/// Pod held *before* the faster one had finished — which quietly discards a
/// key that has just been written, and hands the next write a short map to
/// save over the top of the full one. Deriving the master key twice is worse
/// still on a Pod that is being migrated to the current key format, since the
/// migration rewrites every key.
///
/// Asking for both, once, and waiting for the answer before anything else
/// starts, closes both windows: from then on the map is in memory and no
/// further reads of it are made.

class PodKeys {
  const PodKeys._();

  static Future<void>? _priming;
  static bool _primed = false;

  /// Whether the keys are already in memory.

  static bool get isPrimed => _primed;

  /// Read the master key and the individual key map, once.
  ///
  /// Callers that arrive while the first call is still running wait for that
  /// call rather than starting another. A failure is logged and the next
  /// caller tries again; there is nothing useful to report to the user here,
  /// because whatever they were doing will fail with its own message.

  static Future<void> prime() {
    if (_primed) return Future<void>.value();
    return _priming ??= _prime();
  }

  static Future<void> _prime() async {
    try {
      // Without a security key there is no master key to derive and nothing
      // to decrypt the individual keys with, so there is nothing to do yet.

      if (!await KeyManager.hasSecurityKey()) return;

      // The URL is immaterial: the call is made for the read of the key file
      // that it forces, not for the key it returns, and the album's own
      // container is never in the map.

      await KeyManager.getIndividualKey(
        await getDirUrl(await getDataDirPath()),
      );
      _primed = true;
    } on Object catch (e) {
      debugPrint('PhotoPod: could not read the Pod keys: $e');
    } finally {
      _priming = null;
    }
  }

  /// Forget that the keys have been read, so that the next caller reads them
  /// again. Used when the user logs out or changes their security key.

  static void reset() {
    _primed = false;
    _priming = null;
  }
}
