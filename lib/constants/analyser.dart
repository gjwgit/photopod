/// The Analyser, which finds the faces and the tags in PhotoPod photos.
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

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// The Analyser, set up as HealthPod's blood pressure analyser is.
///
/// The Analyser is a Pod, on the user's Solid server or any other. Identify
/// People, or Tag Photos, shares the user's face inbox, or tag inbox, holding
/// the photos chosen, with its WebID until they are answered; the Solid
/// server tells a service logged in as the Analyser (analyser/face_analyser
/// in this repository), which writes what it finds back into the inbox. The
/// app never talks to that service, so it needs no address of it: [webId]
/// is all there is to know.
///
/// The WebID is configured in [configAsset], so that moving the Analyser to
/// another Solid server means editing that file alone. A build may instead
/// choose another Analyser with
/// `--dart-define=ANALYSER_WEBID=https://.../profile/card#me`, which takes
/// precedence over the file.

class Analyser {
  const Analyser._();

  /// The configuration file holding the Analyser's WebID, as `webId`.

  static const String configAsset = 'assets/config/analyser.json';

  /// The WebID chosen at build time, if any.

  static const String _webIdOverride = String.fromEnvironment('ANALYSER_WEBID');

  static Future<String>? _webId;

  /// The WebID the inboxes are shared with, read once from [configAsset]
  /// unless chosen at build time.

  static Future<String> webId() => _webId ??= _loadWebId();

  static Future<String> _loadWebId() async {
    if (_webIdOverride.isNotEmpty) return _webIdOverride;
    try {
      final config = jsonDecode(await rootBundle.loadString(configAsset));
      final webId = config is Map<String, dynamic> ? config['webId'] : null;
      if (webId is String && webId.isNotEmpty) return webId;
      throw const FormatException('webId is missing or empty');
    } on Object catch (e) {
      // Let a later call try again rather than keep the failure.

      _webId = null;
      throw StateError('The Analyser is not configured in $configAsset: $e');
    }
  }

  /// Name shown in the interface, in place of the raw WebID.

  static const String displayName = 'PhotoPod Analyser';

  /// Who the catalog credits with the people and the tags the Analyser
  /// found, as suggestions the user may keep, change or remove in Get Info.
  /// Shown as [displayName].

  static const String source = 'photopod:analyser';
}
