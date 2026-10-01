/// Tests for telling apart albums and photos other people have shared.
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

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/shared_with_me.dart';
import 'package:photopod/widgets/media_grid.dart';

SharedAlbum _album(String name, String owner) {
  final pod = Uri.parse(owner).replace(path: '/', fragment: '').toString();
  final user = webIdLabel(owner);
  return SharedAlbum(
    name: name,
    url: '$pod$user/photopod/data/albums/$name.json',
    ownerWebId: owner,
    itemUrls: const {},
  );
}

const _alice = 'https://pods.example.org/alice/profile/card#me';
const _bob = 'https://pods.example.org/bob/profile/card#me';
const _otherAlice = 'https://elsewhere.example.net/alice/profile/card#me';

void main() {
  group('sharedAlbumTitles', () {
    test('keeps the name of an album no other album shares', () {
      final album = _album('Holiday', _alice);
      expect(sharedAlbumTitles([album], const ['Family']), {
        album.url: 'Holiday',
      });
    });

    test('adds who shared it when two people share albums of one name', () {
      final a = _album('Holiday', _alice);
      final b = _album('holiday', _bob);
      final titles = sharedAlbumTitles([a, b], const []);
      expect(titles[a.url], 'Holiday (alice)');
      expect(titles[b.url], 'holiday (bob)');
    });

    test('adds who shared it when it has the name of one of the user\'s', () {
      final a = _album('Holiday', _alice);
      expect(
        sharedAlbumTitles([a], const ['Holiday'])[a.url],
        'Holiday (alice)',
      );
    });

    test('uses the fuller WebID when two sharers have the same short name', () {
      final a = _album('Holiday', _alice);
      final b = _album('Holiday', _otherAlice);
      final titles = sharedAlbumTitles([a, b], const []);
      expect(titles[a.url], 'Holiday (pods.example.org/alice/profile/card)');
      expect(
        titles[b.url],
        'Holiday (elsewhere.example.net/alice/profile/card)',
      );
    });

    test('never gives two albums the same title', () {
      final a = _album('Holiday (alice)', _bob);
      final b = _album('Holiday', _alice);
      final c = _album('Holiday', _bob);
      final titles = sharedAlbumTitles([a, b, c], const []);
      expect(titles.values.map((t) => t.toLowerCase()).toSet(), hasLength(3));
    });
  });

  test('compareSharedAlbums orders albums of one name by who shared them', () {
    final albums = [_album('Holiday', _bob), _album('Holiday', _alice)]
      ..sort(compareSharedAlbums);
    expect(albums.map((a) => a.ownerWebId), [_alice, _bob]);
  });

  group('hover text', () {
    const own = MediaItem(
      name: 'my_photo_1.jpg',
      rawName: 'my_photo_1.jpg',
      path: 'photopod/data/my_photo_1.jpg',
      url: 'https://pods.example.org/me/photopod/data/my_photo_1.jpg',
      isFolder: false,
    );
    const shared = MediaItem(
      name: 'beach.jpg',
      rawName: 'beach.jpg',
      path: 'https://pods.example.org/alice/photopod/data/beach.jpg',
      url: 'https://pods.example.org/alice/photopod/data/beach.jpg',
      isFolder: false,
      sharedBy: _alice,
    );

    test('shows only the name of the user\'s own photo', () {
      expect(mediaTooltipMarkdown(own), r'**my\_photo\_1\.jpg**');
      expect(mediaTooltipText(own), 'my_photo_1.jpg');
    });

    test('shows who shared a photo shared with the user', () {
      expect(mediaTooltipMarkdown(shared), contains('Shared by alice'));
      expect(mediaTooltipText(shared), 'beach.jpg\nShared by alice\n$_alice');
    });
  });
}
