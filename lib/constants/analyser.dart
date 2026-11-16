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
/// Another Analyser is chosen at build time with
/// `--dart-define=ANALYSER_WEBID=https://.../profile/card#me`.

class Analyser {
  const Analyser._();

  /// The WebID the inboxes are shared with.

  static const String webId = String.fromEnvironment(
    'ANALYSER_WEBID',
    defaultValue: 'https://solid.dev.empwr.au/Analyser/profile/card#me',
  );

  /// Name shown in the interface, in place of the raw WebID.

  static const String displayName = 'PhotoPod Analyser';

  /// Who the catalog credits with the people and the tags the Analyser
  /// found, as suggestions the user may keep, change or remove in Get Info.
  /// Shown as [displayName].

  static const String source = 'photopod:analyser';
}
