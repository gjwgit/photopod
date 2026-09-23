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

import 'package:provider/provider.dart';
import 'package:solidui/solidui.dart';

import 'package:photopod/constants/app.dart';
import 'package:photopod/models/favourites.dart';
import 'package:photopod/models/library_section.dart';
import 'package:photopod/screens/map_view.dart';
import 'package:photopod/screens/media_browser.dart';

final _scaffoldController = SolidScaffoldController();

/// The scaffold handed to [SolidLogin] as the page to show once the user is
/// connected to their Pod.

const appScaffold = AppScaffold();

/// The application frame: navigation rail, app bar, status bar and the
/// section currently being looked at.
///
/// Each section is given a distinct key because three of the four are a
/// [MediaBrowser] and, without them, moving between Library and Videos would
/// reuse one section's state — and so its folder and its selection — for the
/// other.

class AppScaffold extends StatefulWidget {
  const AppScaffold({super.key});

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  @override
  void initState() {
    super.initState();

    // The hearts live in the Pod, so they can only be read once the login
    // flow has finished — which is exactly when this scaffold first appears.

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<Favourites>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SolidScaffold(
      controller: _scaffoldController,
      hideNavRail: false,
      enableProfile: true,
      onLogout: (context) => SolidAuthHandler.instance.handleLogout(context),
      menu: const [
        SolidMenuItem(
          icon: Icons.photo_library_outlined,
          title: 'Library',
          tooltip: '''

            **Library**

            Tap here for everything in your Pod. Photos and videos are mixed
            together as tiles, alongside the folders they are organised into.

            ''',
          child: MediaBrowser(
            key: ValueKey(LibrarySection.library),
            section: LibrarySection.library,
          ),
        ),
        SolidMenuItem(
          icon: Icons.favorite_outline,
          title: 'Favourites',
          tooltip: '''

            **Favourites**

            Tap here for everything you have put a heart on, gathered from
            every folder in your album.

            ''',
          child: MediaBrowser(
            key: ValueKey(LibrarySection.favourites),
            section: LibrarySection.favourites,
          ),
        ),
        SolidMenuItem(
          icon: Icons.movie_outlined,
          title: 'Videos',
          tooltip: '''

            **Videos**

            Tap here for every video in your album, wherever it is filed.
            MP4 and MOV files are shown.

            ''',
          child: MediaBrowser(
            key: ValueKey(LibrarySection.videos),
            section: LibrarySection.videos,
          ),
        ),
        SolidMenuItem(
          icon: Icons.map_outlined,
          title: 'Maps',
          tooltip: '''

            **Maps**

            Tap here to see your photos on a map, placed by the GPS
            coordinates their cameras recorded in them.

            ''',
          child: MapView(key: ValueKey(LibrarySection.maps)),
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

        🖼️ Browse the album as a wall of tiles, photos and videos together;

        ❤️ Put a heart on anything and find it again under Favourites;

        🗺️ See where your photos were taken, on a map;

        ℹ️ Get Info for the size, the camera, the settings and the place;

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
        key: ValueKey(LibrarySection.library),
        section: LibrarySection.library,
      ),
    );
  }
}
