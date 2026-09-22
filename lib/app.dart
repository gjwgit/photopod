/// Orchestrate the primary login widget.
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

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:solidui/solidui.dart';

import 'package:photopod/app_scaffold.dart';
import 'package:photopod/constants/app.dart';
import 'package:photopod/models/view_prefs.dart';

/// The root of the application.
///
/// On startup [SolidLogin] connects to the user's Pod on their chosen Solid
/// server through the standard Solid-OIDC flow, and only then hands over to
/// the app scaffold. The display preferences are provided above the login
/// screen so that the browser finds them already loaded whichever section
/// the user lands on.

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ViewPrefs>(
      create: (context) => ViewPrefs()..load(),
      child: SolidThemeApp(
        title: appTitle,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
          useMaterial3: true,
        ),
        home: SolidLogin(
          title: appTitle.replaceAll(' - ', '\n'),
          image: const AssetImage('assets/images/app_image.jpg'),
          logo: const AssetImage('assets/images/app_icon.png'),
          link: appRepo,

          // The client identifier has to be the URL the profile document is
          // actually served from, which is where PhotoPod's own
          // client-profile.jsonld is published.
          clientId: 'https://gjwgit.github.io/photopod/client-profile.jsonld',
          redirectUris: kIsWeb
              ? ['${Uri.base.origin}/redirect.html']
              : const [
                  'com.togaware.photopod://redirect',
                  'http://localhost:4400/redirect.html',
                ],
          child: appScaffold,
        ),
      ),
    );
  }
}
