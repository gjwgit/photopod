/// Main entry point.
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

import 'package:media_kit/media_kit.dart';
import 'package:solidui/solidui.dart';
import 'package:window_manager/window_manager.dart';

import 'package:photopod/app.dart';
import 'package:photopod/constants/app.dart';

/// Start PhotoPod.
///
/// The function is asynchronous because the window manager and the video
/// player both have to be ready before the first frame is built.

void main() async {
  // Flutter bindings have to be initialised before any plugin is touched,
  // including the window manager used below to set the desktop window title.

  WidgetsFlutterBinding.ensureInitialized();

  // media_kit sets up its native video backend here rather than lazily, so
  // that the first video the user previews starts without a stutter.

  MediaKit.ensureInitialized();

  if (isDesktop) {
    await windowManager.ensureInitialized();

    // An album wants room to show a grid of thumbnails, so PhotoPod opens
    // wider than it is tall and refuses to be squeezed below a size where
    // the toolbar would no longer fit.

    const windowOptions = WindowOptions(
      title: appTitle,
      size: Size(1200, 800),
      minimumSize: Size(560, 640),
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const App());
}
