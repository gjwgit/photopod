/// Which analyser the user has chosen to find faces and tags.
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

import 'package:shared_preferences/shared_preferences.dart';

import 'package:photopod/constants/teepod.dart';
import 'package:photopod/services/teepod/teepod.dart';

/// The analysers Identify People and Tag Photos can send photos to. Both run
/// the same models and their answers are filed the same way; they differ in
/// how private the photos stay while they are looked at.

enum AnalyserBackend {
  /// TeePod, in a trusted execution environment, which proves what it is
  /// before PhotoPod sends it anything. See lib/services/teepod/.

  teePod('TeePod', 'Higher privacy'),

  /// The Pod Analyser on the Solid Community server, which reads the photos
  /// from an inbox in the user's Pod shared with it. See
  /// lib/services/analyser_inbox.dart.

  solidCommunity('Solid Community', 'Limited privacy');

  const AnalyserBackend(this.label, this.privacy);

  /// The name shown in the interface.

  final String label;

  /// How private the photos stay, in a few words.

  final String privacy;
}

/// The analyser chosen on this device, or none until the user has chosen.
///
/// The choice is the user's to make, since the two analysers keep photos
/// private to different degrees, so PhotoPod asks the first time photos are
/// to be looked at rather than choosing for them, and the user may change
/// it at any time from People or Tags. Like the display preferences, it is
/// held on the device and never written to the Pod.

class AnalyserChoice extends ChangeNotifier {
  static const _key = 'photopod.analyser';

  AnalyserBackend? _chosen;
  Future<void>? _loading;

  /// The analyser chosen, or null when the user has not chosen yet.

  AnalyserBackend? get chosen => _chosen;

  /// Read the stored choice, once.

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_key);
      for (final backend in AnalyserBackend.values) {
        if (backend.name == name) _chosen = backend;
      }
    } on Object catch (e) {
      debugPrint('PhotoPod: could not read the analyser chosen: $e');
    }
    notifyListeners();
  }

  /// Remember [backend] as the analyser to use from now on.

  Future<void> choose(AnalyserBackend backend) async {
    if (backend == _chosen) return;
    _chosen = backend;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, backend.name);
  }

  /// Whether this build can reach TeePod: the web cannot (see
  /// support/teepod/WEB.md), nor a native build without TeePod's client
  /// certificate.

  static Future<bool> teePodAvailable() async {
    if (!TeePod.isSupported) return false;
    try {
      return await TeePodConfig.load() != null;
    } on Object catch (e) {
      debugPrint('PhotoPod: TeePod is not configured: $e');
      return false;
    }
  }
}
