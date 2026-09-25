/// App-wide constants.
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

import 'package:solidui/solidui.dart' show SolidInviteOthersConfig;

/// Application title displayed as the window title.

const String appTitle = 'PhotoPod - Photo and Video Album for Solid Pods';

/// Short name of the application, used in the app bar and dialogues.

const String appName = 'PhotoPod';

/// Public URL where PhotoPod is hosted. Used by the Invite Others feature to
/// send a working link to the recipient.

const String appUrl = 'https://photopod.solidcommunity.au/';

/// The GitHub repository for the application.

const String appRepo = 'https://github.com/anusii/photopod';

/// Application-wide Invite Others configuration shared by the AppBar share
/// button and the App Info dialog so that users can invite others to set up
/// their Pod and try PhotoPod.

const SolidInviteOthersConfig inviteOthersConfig = SolidInviteOthersConfig(
  applicationName: appName,
  appUrl: appUrl,
  appDescription:
      'store, browse and share photos and videos held on your Solid server '
      'using PhotoPod',
  messageTemplate: '''
You might like to try the {appName} app, available online here:

{appUrl}

Signing into {appName} will set up your data vault so you can keep your photos
and videos privately in your own Pod and share them with other Solid users.

''',
  subject: 'Try the PhotoPod app on your Solid Pod',
  tooltip: '''

  **Invite Others**

  Tap to invite someone else to try PhotoPod. You can copy the
  invitation to the clipboard or share it through any messaging app
  installed on your device.

  ''',
);
