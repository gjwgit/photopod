/// Sample photos shown to someone who has not logged in.
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

import 'package:flutter/services.dart';

import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/photo_metadata.dart';

/// One sample photo or video bundled with the app.

class DemoEntry {
  /// The file name under [DemoLibrary.assetFolder].

  final String file;

  /// The name shown for it, extension included.

  final String name;

  /// When it was taken. Each photo carries the same date in its EXIF block,
  /// so Get Info agrees with the timeline.

  final DateTime taken;

  /// The people in it, for the portraits, which sorts each sample into the
  /// faces or the nature album.

  final List<String> people;

  /// A still frame bundled for a video, which has no thumbnail of its own.

  final String? poster;

  /// Where a video was taken. A photo carries its place in its EXIF block,
  /// but a video has nothing PhotoPod reads, so the place is given here for
  /// the map.

  final double? latitude;
  final double? longitude;

  const DemoEntry(
    this.file,
    this.name,
    this.taken, {
    this.people = const [],
    this.poster,
    this.latitude,
    this.longitude,
  });
}

/// The sample album a visitor sees before logging in.
///
/// PhotoPod is set to skip the login screen, so anyone who opens it lands in
/// the app straight away. With no Pod to read, every section shows this
/// album instead: landscapes from around the world, each carrying GPS
/// coordinates in its EXIF block for the Maps section; dates spread across
/// many years for sorting and the timeline; and recent portraits of three
/// Nobel laureates in physics, several of each, which also appear on the map.
/// None of them is a political figure, and no one else appears in their
/// photos.
///
/// Every photo is from Wikimedia Commons and is in the public domain or
/// released under CC0, so none needs attribution. The photographer is
/// nonetheless recorded in each file's EXIF Artist field.
///
/// Everything is read from the app bundle. Nothing here is written to a Pod,
/// and nothing a visitor does to it outlives the session.

class DemoLibrary {
  const DemoLibrary._();

  /// The folder within the app bundle that holds the samples.

  static const String assetFolder = 'assets/demo';

  /// The stand-in for the album root, which only ever appears in paths.

  static const String root = 'demo';

  /// Every sample item's URL starts with this, which is how a sample is told
  /// apart from a file in a Pod.

  static const String urlPrefix = 'asset:$assetFolder/';

  /// The name of the sample album gathering the landscapes.

  static const String natureAlbum = 'Around the World';

  /// The name of the sample album gathering the portraits.

  static const String faceAlbum = 'Nobel Laureates';

  static final List<DemoEntry> entries = [
    // Landscapes, across six continents.
    DemoEntry(
      'grand_canyon.jpg',
      'Grand Canyon, USA.jpg',
      DateTime(2025, 6, 14, 6, 12),
    ),
    DemoEntry(
      'yosemite.jpg',
      'Yosemite Valley, USA.jpg',
      DateTime(2025, 6, 21, 17, 40),
    ),
    DemoEntry(
      'moraine_lake.jpg',
      'Moraine Lake, Canada.jpg',
      DateTime(2025, 8, 3, 9, 5),
    ),
    DemoEntry(
      'machu_picchu.jpg',
      'Machu Picchu, Peru.jpg',
      DateTime(2024, 5, 14, 8, 30),
    ),
    DemoEntry(
      'perito_moreno.jpg',
      'Perito Moreno Glacier, Argentina.jpg',
      DateTime(2024, 2, 2, 7, 45),
    ),
    DemoEntry(
      'iceland_waterfall.jpg',
      'Waterfall, Iceland.jpg',
      DateTime(2024, 7, 20, 13, 30),
    ),
    DemoEntry(
      'nordfjord.jpg',
      'Nordfjord, Norway.jpg',
      DateTime(2025, 7, 4, 21, 10),
    ),
    DemoEntry(
      'matterhorn.jpg',
      'Matterhorn, Switzerland.jpg',
      DateTime(2025, 10, 17, 18, 20),
    ),
    DemoEntry(
      'sahara.jpg',
      'Sahara Desert, Morocco.jpg',
      DateTime(2025, 3, 8, 18, 25),
    ),
    DemoEntry(
      'kilimanjaro.jpg',
      'Kilimanjaro, Tanzania.jpg',
      DateTime(2025, 9, 12, 6, 50),
    ),
    DemoEntry(
      'mount_fuji.jpg',
      'Mount Fuji, Japan.jpg',
      DateTime(2026, 3, 22, 17, 45),
    ),
    DemoEntry(
      'ha_long_bay.jpg',
      'Ha Long Bay, Vietnam.jpg',
      DateTime(2026, 4, 11, 15),
    ),
    DemoEntry(
      'great_ocean_road.jpg',
      'Great Ocean Road, Australia.jpg',
      DateTime(2026, 1, 2, 19, 55),
    ),
    DemoEntry(
      'anu_birch_building_2023.mp4',
      'Birch Building, ANU.mp4',
      DateTime(2023, 10, 12, 15),
      poster: 'anu_birch_building_2023_poster.jpg',
      latitude: -35.2743,
      longitude: 149.1193,
    ),
    DemoEntry(
      'milford_sound.jpg',
      'Milford Sound, New Zealand.jpg',
      DateTime(2026, 1, 9, 12, 40),
    ),

    // Nobel laureates in physics, several portraits each. All are recent
    // photos from NASA, NIST and the Space Telescope Science Institute, so
    // each carries the date and the place it was taken in its EXIF block,
    // and appears on the map with the landscapes. Each photo shows only the
    // person named. Where Wikimedia Commons gives only the year a photo was
    // taken, the month and day are made up.
    DemoEntry(
      'john_mather_2012.jpg',
      'John Mather, 2012.jpg',
      DateTime(2012, 11, 19, 10, 10),
      people: ['John Mather'],
    ),
    DemoEntry(
      'john_mather_webb_2016.jpg',
      'John Mather and the Webb telescope, 2016.jpg',
      DateTime(2016, 5, 4, 14, 25),
      people: ['John Mather'],
    ),
    DemoEntry(
      'john_mather_2016.jpg',
      'John Mather, 2016.jpg',
      DateTime(2016, 11, 28, 13, 35),
      people: ['John Mather'],
    ),
    DemoEntry(
      'john_mather_houston_2017.jpg',
      'John Mather in Houston, 2017.jpg',
      DateTime(2017, 6, 21, 11, 5),
      people: ['John Mather'],
    ),
    DemoEntry(
      'david_wineland_2008.jpg',
      'David Wineland, 2008.jpg',
      DateTime(2008, 9, 15, 11),
      people: ['David Wineland'],
    ),
    DemoEntry(
      'david_wineland_laboratory_2012.jpg',
      'David Wineland in his laboratory, 2012.jpg',
      DateTime(2012, 10, 18, 15),
      people: ['David Wineland'],
    ),
    DemoEntry(
      'david_wineland_2013.jpg',
      'David Wineland, 2013.jpg',
      DateTime(2013, 1, 23, 12, 34, 19),
      people: ['David Wineland'],
    ),
    DemoEntry(
      'adam_riess_2006.jpg',
      'Adam Riess, 2006.jpg',
      DateTime(2006, 6, 22, 10),
      people: ['Adam Riess'],
    ),
    DemoEntry(
      'adam_riess_2008.jpg',
      'Adam Riess, 2008.jpg',
      DateTime(2008, 9, 23, 10),
      people: ['Adam Riess'],
    ),
    DemoEntry(
      'adam_riess_2009.jpg',
      'Adam Riess, 2009.jpg',
      DateTime(2009, 4, 28, 10),
      people: ['Adam Riess'],
    ),
  ];

  /// The samples hearted from the start, so Favourites is not empty.

  static const Set<String> _favourites = {
    'mount_fuji.jpg',
    'matterhorn.jpg',
    'milford_sound.jpg',
    'great_ocean_road.jpg',
  };

  static final Map<String, DemoEntry> _byPath = {
    for (final entry in entries) pathOf(entry.file): entry,
  };

  /// Every sample as the item the sections display.

  static final List<MediaItem> items = List.unmodifiable([
    for (final entry in entries)
      MediaItem(
        name: entry.name,
        rawName: entry.file,
        path: pathOf(entry.file),
        url: '$urlPrefix${entry.file}',
        isFolder: false,
        modified: entry.taken,
        taken: entry.taken,
      ),
  ]);

  /// The stand-in path of the sample stored as [file].

  static String pathOf(String file) => '$root/$file';

  /// Whether [item] is one of the samples rather than a file in a Pod.

  static bool isDemo(MediaItem item) => item.url.startsWith(urlPrefix);

  /// The bytes of the sample [item].

  static Future<Uint8List> read(MediaItem item) async {
    final data = await rootBundle.load('$assetFolder/${item.rawName}');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// The still frame bundled for the sample video [item], if it has one.

  static Future<Uint8List?> poster(MediaItem item) async {
    final poster = _byPath[item.path]?.poster;
    if (poster == null) return null;
    final data = await rootBundle.load('$assetFolder/$poster');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// What is known of the sample video [item] without decoding it: when and
  /// where it was taken. Null for a photo, which says that itself.

  static PhotoMetadata? videoMetadataOf(MediaItem item) {
    final entry = _byPath[item.path];
    if (entry == null || entry.poster == null) return null;
    return PhotoMetadata(
      taken: entry.taken,
      latitude: entry.latitude,
      longitude: entry.longitude,
    );
  }

  /// The sample videos that know where they were taken, for the map.

  static Iterable<MediaItem> get placedVideos => items.where(
    (item) =>
        item.isVideo &&
        _byPath[item.path]?.latitude != null &&
        _byPath[item.path]?.longitude != null,
  );

  /// The paths of the samples hearted from the start.

  static Set<String> get favourites => {
    for (final file in _favourites) pathOf(file),
  };

  /// The sample albums, by name, each a set of paths.

  static Map<String, Set<String>> get albums => {
    // Everything with nobody in it: the landscapes and the video.
    natureAlbum: {
      for (final entry in entries)
        if (entry.people.isEmpty) pathOf(entry.file),
    },
    faceAlbum: {
      for (final entry in entries)
        if (entry.people.isNotEmpty) pathOf(entry.file),
    },
  };
}
