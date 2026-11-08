/// Tests for the sample album shown before login.
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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:photopod/services/demo_library.dart';
import 'package:photopod/services/thumbnail_cache.dart';

void main() {
  final paths = {for (final item in DemoLibrary.items) item.path};

  test('every sample is in the app bundle', () {
    for (final entry in DemoLibrary.entries) {
      final asset = '${DemoLibrary.assetFolder}/${entry.file}';
      expect(File(asset).existsSync(), isTrue, reason: asset);
      final poster = entry.poster;
      if (poster != null) {
        final still = '${DemoLibrary.assetFolder}/$poster';
        expect(File(still).existsSync(), isTrue, reason: still);
      }
    }
  });

  test('every sample is told apart from a file in a Pod', () {
    expect(DemoLibrary.items, hasLength(DemoLibrary.entries.length));
    expect(paths, hasLength(DemoLibrary.entries.length));
    expect(DemoLibrary.items.every(DemoLibrary.isDemo), isTrue);
    expect(DemoLibrary.items.every((item) => item.taken != null), isTrue);
  });

  test('the hearts and albums name only samples that exist', () {
    expect(paths.containsAll(DemoLibrary.favourites), isTrue);
    for (final album in DemoLibrary.albums.values) {
      expect(album, isNotEmpty);
      expect(paths.containsAll(album), isTrue);
    }
  });

  test('the photos carry the date and the place the app relies on', () {
    for (final entry in DemoLibrary.entries) {
      if (entry.poster != null) continue;
      final bytes = File(
        '${DemoLibrary.assetFolder}/${entry.file}',
      ).readAsBytesSync();
      final metadata = readExifMetadata(img.decodeJpg(bytes)!);

      expect(metadata.taken, entry.taken, reason: entry.file);

      // The landscapes and the portraits alike appear on the map.

      expect(metadata.hasLocation, isTrue, reason: entry.file);
    }
  });

  test('the portraits give each of three people several photos', () {
    final counts = <String, int>{};
    for (final entry in DemoLibrary.entries) {
      for (final who in entry.people) {
        counts[who] = (counts[who] ?? 0) + 1;
      }
    }
    expect(counts, hasLength(3));
    expect(counts.values.every((count) => count >= 2), isTrue);
  });

  test('every downloaded photo is in the public domain or under CC0', () {
    for (final entry in DemoLibrary.entries) {
      // The video is the authors' own.
      if (entry.poster != null) continue;
      final bytes = File(
        '${DemoLibrary.assetFolder}/${entry.file}',
      ).readAsBytesSync();
      final exif = img.decodeJpgExif(bytes)!;
      final copyright = '${exif.imageIfd['Copyright']}';
      expect(
        copyright.contains('Public domain') || copyright.contains('CC0'),
        isTrue,
        reason: '${entry.file}: $copyright',
      );
    }
  });

  test('the video has a place for the map', () {
    final videos = DemoLibrary.items.where((item) => item.isVideo).toList();
    expect(videos, isNotEmpty);
    expect(DemoLibrary.placedVideos, hasLength(videos.length));
    for (final video in videos) {
      final metadata = DemoLibrary.videoMetadataOf(video)!;
      expect(metadata.hasLocation, isTrue);
      expect(metadata.taken, video.taken);
    }
  });
}
