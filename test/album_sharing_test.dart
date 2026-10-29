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
import 'package:photopod/services/share_decline.dart';
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
      expect(albumNameOf('$root/favourites.json.enc.ttl'), 'Favourites');
      expect(albumNameOf('$root/albums/Holiday.json.enc.ttl'), 'Holiday');
      expect(
        isAlbumUrl('$root/albums/Holiday.json.enc.ttl', 'photopod/data'),
        isTrue,
      );
      expect(isAlbumUrl('$root/albums/Holiday.txt', 'photopod/data'), isFalse);
      expect(
        isAlbumUrl('$root/favourites.json.enc.ttl', 'photopod/data'),
        isTrue,
      );
      expect(
        podRootOf('$root/albums/Holiday.json', 'photopod/data'),
        'https://pod.example/alice/',
      );
      expect(
        isAlbumUrl('$root/albums/sub/Holiday.json', 'photopod/data'),
        isFalse,
      );
    });

    test('a declined photo stays declined, until it is shared again', () {
      final url = '$root/beach.jpg.enc.ttl';
      final grant = line('20260930T100000', url, 'grant');

      // The device's clock is behind the one the grant was written with, so
      // the decline is dated a second after the grant instead.

      final query = declineLogQuery(
        url: url,
        owner: alice,
        me: me,
        recipient: me,
        permissions: 'read',
        after: '20260930T100000',
        now: DateTime(2026, 9, 30, 9),
      );
      final declined = RegExp(r'\{(.*)\}').firstMatch(query)!.group(1)!;
      expect(declined, contains('"<20260930T100001;$url;$alice;revoke;'));

      final lines = latestLogLines('$grant\n$declined.');
      expect(lines[url]!.type, 'revoke');
      expect(
        sortSharedLog(lines, me: me, dataDir: 'photopod/data').media,
        isEmpty,
      );

      final again = line('20260930T120000', url, 'grant');
      expect(
        sortSharedLog(
          latestLogLines('$grant\n$declined.\n$again'),
          me: me,
          dataDir: 'photopod/data',
        ).media,
        hasLength(1),
      );
    });

    test('tells the user\'s own photos from ones shared with them', () {
      const own = 'https://pod.example/me/';
      expect(
        ownPathOf('https://pod.example/me/photopod/data/a.jpg.enc.ttl', own),
        'photopod/data/a.jpg.enc.ttl',
      );
      expect(
        ownPathOf('https://POD.example/me/photopod/data/a.jpg.enc.ttl', own),
        'photopod/data/a.jpg.enc.ttl',
      );
      expect(ownPathOf('$root/a.jpg.enc.ttl', own), isNull);
      expect(ownPathOf('https://pod.example/meg/photopod/a.jpg', own), isNull);
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
