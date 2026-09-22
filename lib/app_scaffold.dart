/// The primary application scaffold.
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

import 'package:solidui/solidui.dart';

import 'package:photopod/constants/app.dart';
import 'package:photopod/constants/media.dart';
import 'package:photopod/screens/media_browser.dart';

final _scaffoldController = SolidScaffoldController();

/// The scaffold handed to [SolidLogin] as the page to show once the user is
/// connected to their Pod.

const appScaffold = AppScaffold();

/// The application frame: navigation bar, app bar, status bar and the section
/// currently being looked at.
///
/// The two sections are given distinct keys because both are a [MediaBrowser]
/// and, without them, moving between Photos and Videos would reuse one
/// section's state — and so its folder and selection — for the other.

class AppScaffold extends StatelessWidget {
  const AppScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return SolidScaffold(
      controller: _scaffoldController,
      hideNavRail: false,
      enableProfile: true,
      onLogout: (context) => SolidAuthHandler.instance.handleLogout(context),
      menu: const [
        SolidMenuItem(
          icon: Icons.photo_library,
          title: 'Photos',
          tooltip: '''

            **Photos**

            Tap here for the photos in your Pod. JPG, PNG, GIF and TIFF files
            are shown, along with the folders they are organised into.

            ''',
          child: MediaBrowser(
            key: ValueKey(MediaKind.photo),
            kind: MediaKind.photo,
          ),
        ),
        SolidMenuItem(
          icon: Icons.video_library,
          title: 'Videos',
          tooltip: '''

            **Videos**

            Tap here for the videos in your Pod. MP4 and MOV files are shown,
            along with the folders they are organised into.

            ''',
          child: MediaBrowser(
            key: ValueKey(MediaKind.video),
            kind: MediaKind.video,
          ),
        ),
      ],
      appBar: const SolidAppBarConfig(
        title: appName,
        versionConfig: SolidVersionConfig(
          changelogUrl: '$appRepo/blob/dev/CHANGELOG.md',
          showUpdateButton: true,
          downloadUrl: 'https://solidcommunity.au/installers/',
        ),
      ),
      statusBar: const SolidStatusBarConfig(
        serverInfo: SolidServerInfo(serverUri: SolidConfig.defaultServerUrl),
        loginStatus: SolidLoginStatus(),
        securityKeyStatus: SolidSecurityKeyStatus(),
      ),
      aboutConfig: SolidAboutConfig(
        applicationName: appName,
        applicationIcon: Image.asset(
          'assets/images/app_icon.png',
          width: 64,
          height: 64,
        ),
        applicationLegalese: '''

        © 2026 Software Innovation Institute, ANU

        ''',
        text:
            '''

        PhotoPod keeps your photos and videos in your own personal online data
        store (Pod) on a Solid server, where they stay yours.

        Key features:

        🖼️ Browse photos as thumbnails or as a detailed list;

        🎬 Play videos without leaving the app;

        📁 Organise everything into folders;

        ➕ Add, delete, copy, move and rename files and folders;

        🔐 Share photos and videos with other Solid users by WebID;

        ↕️ Sort by name or by date, and page through large albums;

        🎨 Theme switching (light/dark/system);

        🧭 Responsive navigation (rail ↔ drawer).

        For more information, visit the
        [PhotoPod]($appRepo) GitHub repository and our
        [Australian Solid Community](https://solidcommunity.au) web site.

        ''',
      ),
      themeToggle: const SolidThemeToggleConfig(
        enabled: true,
        showInAppBarActions: true,
      ),
      inviteConfig: inviteOthersConfig,
      child: const MediaBrowser(
        key: ValueKey(MediaKind.photo),
        kind: MediaKind.photo,
      ),
    );
  }
}
