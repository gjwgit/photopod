/// Tests for sharing albums and for what is shared with the user.
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
import 'package:solidpod/solidpod.dart' show RecipientType;

import 'package:photopod/services/album_sharing.dart';
import 'package:photopod/services/shared_with_me.dart';

const _bob = 'https://pod.example/bob/profile/card#me';
const _carol = 'https://pod.example/carol/profile/card#me';

ShareRecipient _to(String key, [Set<String> modes = const {'Read'}]) =>
    ShareRecipient(key: key, type: RecipientType.individual, modes: modes);

AlbumGrant _granted([Set<String> modes = const {'Read'}]) =>
    AlbumGrant(type: RecipientType.individual, modes: modes);

void main() {
  group('planSharing', () {
    test('shares everything in an album with everyone it is shared with', () {
      final changes = planSharing(
        albums: {
          'Holiday': {
            'photopod/data/a.jpg.enc.ttl',
            'photopod/data/b.jpg.enc.ttl',
          },
        },
        recipients: {
          'Holiday': {_bob: _to(_bob)},
        },
        grants: const {},
      );

      expect(changes, hasLength(2));
      expect(changes.every((change) => !change.ends), isTrue);
      expect(changes.map((change) => change.key).toSet(), {_bob});
    });

    test('changes nothing once the photos are already shared', () {
      final changes = planSharing(
        albums: {
          'Holiday': {'photopod/data/a.jpg.enc.ttl'},
        },
        recipients: {
          'Holiday': {_bob: _to(_bob)},
        },
        grants: {
          'photopod/data/a.jpg.enc.ttl': {_bob: _granted()},
        },
      );

      expect(changes, isEmpty);
    });

    test('keeps a photo shared while another shared album still holds it', () {
      // Holiday is no longer shared with Bob, but Beach, which holds the
      // same photo, still is.

      final changes = planSharing(
        albums: {
          'Holiday': {
            'photopod/data/a.jpg.enc.ttl',
            'photopod/data/b.jpg.enc.ttl',
          },
          'Beach': {'photopod/data/a.jpg.enc.ttl'},
        },
        recipients: {
          'Beach': {_bob: _to(_bob)},
        },
        grants: {
          'photopod/data/a.jpg.enc.ttl': {_bob: _granted()},
          'photopod/data/b.jpg.enc.ttl': {_bob: _granted()},
        },
      );

      expect(changes, hasLength(1));
      expect(changes.single.path, 'photopod/data/b.jpg.enc.ttl');
      expect(changes.single.ends, isTrue);
    });

    test('unshares a photo taken out of the only shared album holding it', () {
      final changes = planSharing(
        albums: {
          'Holiday': {'photopod/data/b.jpg.enc.ttl'},
        },
        recipients: {
          'Holiday': {_bob: _to(_bob)},
        },
        grants: {
          'photopod/data/a.jpg.enc.ttl': {_bob: _granted()},
          'photopod/data/b.jpg.enc.ttl': {_bob: _granted()},
        },
      );

      expect(changes.single.path, 'photopod/data/a.jpg.enc.ttl');
      expect(changes.single.ends, isTrue);
    });

    test('gives each recipient the most any of the albums gives them', () {
      final changes = planSharing(
        albums: {
          'Holiday': {'photopod/data/a.jpg.enc.ttl'},
          'Beach': {'photopod/data/a.jpg.enc.ttl'},
        },
        recipients: {
          'Holiday': {_bob: _to(_bob)},
          'Beach': {
            _bob: _to(_bob, {'Read', 'Write'}),
            _carol: _to(_carol),
          },
        },
        grants: const {},
      );

      final byKey = {for (final change in changes) change.key: change};
      expect(byKey[_bob]!.modes, {'Read', 'Write'});
      expect(byKey[_carol]!.modes, {'Read'});
    });

    test('narrows the access when the wider album is unshared', () {
      final changes = planSharing(
        albums: {
          'Holiday': {'photopod/data/a.jpg.enc.ttl'},
          'Beach': {'photopod/data/a.jpg.enc.ttl'},
        },
        recipients: {
          'Holiday': {_bob: _to(_bob)},
        },
        grants: {
          'photopod/data/a.jpg.enc.ttl': {
            _bob: _granted({'Read', 'Write'}),
          },
        },
      );

      expect(changes.single.ends, isFalse);
      expect(changes.single.modes, {'Read'});
    });

    test('leaves out photos someone else shared with the user', () {
      final changes = planSharing(
        albums: {
          'Holiday': {'https://pod.example/alice/photopod/data/a.jpg.enc.ttl'},
        },
        recipients: {
          'Holiday': {_bob: _to(_bob)},
        },
        grants: const {},
      );

      expect(changes, isEmpty);
    });
  });

  group('what is shared with the user', () {
    const me = 'https://pod.example/me/profile/card#me';
    const alice = 'https://pod.example/alice/profile/card#me';
    const root = 'https://pod.example/alice/photopod/data';

    // A log line exactly as solidpod writes it into the recipient's log.

    String line(String time, String url, String type, {String to = me}) =>
        'logId:${time}000 data:log "<$time;$url;$alice;$type;$alice;$to;'
        'read>".';

    test('sorts photos from albums and drops what was revoked', () {
      final log =
          """
@prefix logId: <https://solidcommunity.au/predicates/logid#> .
@prefix data: <https://solidcommunity.au/predicates/data#> .
${line('20260930T100000', '$root/beach.jpg.enc.ttl', 'grant')}
${line('20260930T100000', '$root/gone.jpg.enc.ttl', 'grant')}
${line('20260930T110000', '$root/gone.jpg.enc.ttl', 'revoke')}
${line('20260930T100000', '$root/albums/Holiday.json', 'grant')}
${line('20260930T100000', '$root/favourites.json', 'grant')}
${line('20260930T100000', 'https://pod.example/alice/notepod/data/n.ttl', 'grant')}
${line('20260930T100000', '$root/notes.txt', 'grant')}
logId:broken data:log "<not a log line>".
""";

      final sorted = sortSharedLog(
        latestLogLines(log),
        me: me,
        dataDir: 'photopod/data',
      );

      expect(sorted.media.map((each) => each.url), ['$root/beach.jpg.enc.ttl']);
      expect(sorted.albums.map((each) => each.url).toSet(), {
        '$root/albums/Holiday.json',
        '$root/favourites.json',
      });
      expect(sorted.albums.first.owner, alice);
    });

    test('takes a share made again after being revoked', () {
      final log = [
        line('20260930T100000', '$root/albums/Holiday.json', 'grant'),
        line('20260930T110000', '$root/albums/Holiday.json', 'revoke'),
        line('20260930T120000', '$root/albums/Holiday.json', 'grant'),
      ].join('\n');

      final sorted = sortSharedLog(
        latestLogLines(log),
        me: me,
        dataDir: 'photopod/data',
      );

      expect(sorted.albums, hasLength(1));
    });

    test('does not mind how the sharer spelt the WebID', () {
      final log = line(
        '20260930T100000',
        '$root/albums/Holiday.json',
        'grant',
        to: 'https://POD.example/me/profile/card',
      );

      final sorted = sortSharedLog(
        latestLogLines(log),
        me: me,
        dataDir: 'photopod/data',
      );

      expect(sorted.albums, hasLength(1));
      expect(sameWebId(me), sameWebId('https://POD.example/me/profile/card'));
    });

    test('leaves out the user\'s own sharing', () {
      final log =
          'logId:1 data:log "<20260930T100000;$root/a.jpg.enc.ttl;$me;grant;'
          '$me;$alice;read>".';

      final sorted = sortSharedLog(
        latestLogLines(log),
        me: me,
        dataDir: 'photopod/data',
      );

      expect(sorted.media, isEmpty);
    });

    test('names shared albums and finds the Pod they live in', () {
      expect(albumNameOf('$root/albums/Holiday.json'), 'Holiday');
      expect(albumNameOf('$root/favourites.json'), 'Favourites');
      expect(
        podRootOf('$root/albums/Holiday.json', 'photopod/data'),
        'https://pod.example/alice/',
      );
      expect(
        isAlbumUrl('$root/albums/sub/Holiday.json', 'photopod/data'),
        isFalse,
      );
    });

    test('names the owner from their WebID', () {
      expect(webIdLabel(alice), 'alice');
      expect(
        webIdLabel('https://alice.solidcommunity.net/profile/card#me'),
        'alice',
      );
    });
  });
}
