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
/// The Analyser is a Pod on the same Solid server as the user's. Turning
/// People on shares the user's face inbox with it; a service beside the
/// server (analyser/face_analyser in this repository), logged in as the
/// Analyser, looks at every shared inbox and writes the faces it finds back
/// into it. The app never talks to that service, so it needs no address of
/// it: [webId] is all there is to know.

class FaceAnalyser {
  const FaceAnalyser._();

  /// The WebID the face inbox is shared with.

  static const String webId =
      'https://solid.dev.empwr.au/Analyser/profile/card#me';

  /// Name shown in the interface, in place of the raw WebID.

  static const String displayName = 'PhotoPod Analyser';
}
