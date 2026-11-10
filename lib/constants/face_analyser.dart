/// The Analyser: the service that finds the faces in PhotoPod photos.
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

/// The face Analyser, set up as HealthPod's blood pressure analyser is.
///
/// Two addresses matter, and they are separate on purpose:
///
///   * [webId] is the Analyser's Pod. The face inbox is shared with it, and
///     the results are shared back from it. This is all the Solid server
///     knows about.
///
///   * [serviceUrl] is the service, analyser/face_analyser in this
///     repository, running beside the Solid server. PhotoPod calls it only to
///     say "look now" and to say which results it has taken; no photo is
///     ever sent to it. Every call carries the user's Solid login, so it can
///     only start a run for the caller's own Pod.

class FaceAnalyser {
  const FaceAnalyser._();

  /// The WebID the face inbox is shared with.

  static const String webId =
      'https://solid.dev.empwr.au/Analyser/profile/card#me';

  /// Name shown in the interface, in place of the raw WebID.

  static const String displayName = 'PhotoPod Analyser';

  /// Where the service listens, without `/v1/...`, which a build can change
  /// with `--dart-define=PHOTOPOD_FACE_ANALYSER=https://...`. It must equal
  /// `service.public_url` in the analyser's configuration.

  static const String serviceUrl = String.fromEnvironment(
    'PHOTOPOD_FACE_ANALYSER',
    defaultValue: 'https://solid.dev.empwr.au/photopod-faces',
  );
}
