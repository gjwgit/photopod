/// Tests for the routes a copy of a photo or video can be shared by.
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

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/share_route.dart';

MediaItem _item(String name, {bool isFolder = false}) => MediaItem(
  name: name,
  rawName: name,
  path: 'photopod/data/$name',
  url: 'https://pod.example/photopod/data/$name',
  isFolder: isFolder,
);

void main() {
  final photo = _item('beach.jpg');
  final video = _item('surf.mp4');

  // Each test sets the platform it pretends to run on, and puts it back.

  List<ShareRoute> onAll(TargetPlatform platform, List<MediaItem> items) {
    debugDefaultTargetPlatformOverride = platform;
    try {
      return shareRoutesFor(items);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  List<ShareRoute> on(TargetPlatform platform, MediaItem item) =>
      onAll(platform, [item]);

  test('a phone goes straight to its share sheet', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(on(platform, photo), [ShareRoute.sheet]);
      expect(on(platform, video), [ShareRoute.sheet]);
    }
  });

  test('macOS and Windows offer the share sheet and the clipboard', () {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
      expect(on(platform, photo), [ShareRoute.sheet, ShareRoute.copy]);
      expect(on(platform, video), [ShareRoute.sheet, ShareRoute.copy]);
    }
  });

  test('Linux, with no share sheet, offers the clipboard alone', () {
    expect(on(TargetPlatform.linux, photo), [ShareRoute.copy]);
    expect(on(TargetPlatform.linux, video), [ShareRoute.copy]);
  });

  test('a folder or an unknown file cannot be shared this way', () {
    expect(on(TargetPlatform.android, _item('2026', isFolder: true)), isEmpty);
    expect(on(TargetPlatform.macOS, _item('notes.txt')), isEmpty);
  });

  test('several files go to the share sheet, or on as files', () {
    final both = [photo, video, _item('2026', isFolder: true)];
    expect(onAll(TargetPlatform.android, both), [ShareRoute.sheet]);
    expect(onAll(TargetPlatform.macOS, both), [
      ShareRoute.sheet,
      ShareRoute.copy,
    ]);
    expect(onAll(TargetPlatform.linux, both), [ShareRoute.copy]);
    expect(shareableFiles(both), [photo, video]);
  });
}
