/// The photos, videos and albums other people have shared with the user.
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

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:solidpod/solidpod.dart'
    show
        PathType,
        getDataDirPath,
        getResource,
        getWebId,
        isUserLoggedIn,
        readPod;

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/albums.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/pod_media_service.dart';
import 'package:photopod/services/share_decline.dart';
import 'package:photopod/services/shared_log.dart';

export 'package:photopod/services/shared_log.dart';

/// An album someone else has shared with the user.

class SharedAlbum {
  /// The album's name as its owner gave it.

  final String name;

  /// The URL of the album file in the owner's Pod, which is also what tells
  /// two shared albums of the same name apart.

  final String url;

  /// The WebID of the album's owner.

  final String ownerWebId;

  /// The URLs of the photos and videos the album holds, except for any of
  /// the user's own, which are given by their Pod-relative path, the
  /// [MediaItem.path] they have in the user's own Library.

  final Set<String> itemUrls;

  const SharedAlbum({
    required this.name,
    required this.url,
    required this.ownerWebId,
    required this.itemUrls,
  });
}

/// The order shared albums are listed in: by name, ignoring case, and then,
/// for albums of the same name from different people, by who shared them and
/// where the album lives, so that the order never changes from one reading
/// of the log to the next.

int compareSharedAlbums(SharedAlbum a, SharedAlbum b) {
  final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  if (byName != 0) return byName;
  final byOwner = sameWebId(a.ownerWebId).compareTo(sameWebId(b.ownerWebId));
  return byOwner != 0 ? byOwner : a.url.compareTo(b.url);
}

/// A short, readable name for [webId], for labels such as "Shared by alice".
///
/// A Solid WebID usually names its owner in the first segment of its path, as
/// in `https://pods.example.org/alice/profile/card#me`; when it does not, the
/// server's host name is the best there is.

String webIdLabel(String webId) {
  final uri = Uri.tryParse(webId);
  if (uri == null) return webId;
  final segments = uri.pathSegments.where((each) => each.isNotEmpty).toList();
  if (segments.isNotEmpty && segments.first != 'profile') {
    return segments.first;
  }
  return uri.host.isEmpty ? webId : uri.host.split('.').first;
}

/// A fuller name for [webId] than [webIdLabel] gives, for telling apart two
/// people whose short names are the same: the WebID without its scheme or
/// fragment, as in `pods.example.org/alice/profile/card`.

String webIdLongLabel(String webId) =>
    sameWebId(webId).replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://'), '');

/// The title each album in [shared] is shown under, by its URL.
///
/// An album keeps its own name when no other album, shared or among the
/// user's own [ownNames], is called the same, ignoring case. Otherwise the
/// name of the person who shared it is added, as in "Holiday (alice)", and
/// where two such people have the same short name their fuller WebIDs are
/// used instead. Anything still alike after that is numbered, so that no two
/// albums are ever listed under the same title.

Map<String, String> sharedAlbumTitles(
  List<SharedAlbum> shared,
  Iterable<String> ownNames,
) {
  final counts = <String, int>{};
  for (final name in [...ownNames, ...shared.map((album) => album.name)]) {
    final key = name.toLowerCase();
    counts[key] = (counts[key] ?? 0) + 1;
  }

  // The short names in use among the sharers of each clashing album name.

  final owners = <String, Map<String, Set<String>>>{};
  for (final album in shared) {
    final key = album.name.toLowerCase();
    if (counts[key]! < 2) continue;
    owners
        .putIfAbsent(key, () => {})
        .putIfAbsent(webIdLabel(album.ownerWebId), () => {})
        .add(sameWebId(album.ownerWebId));
  }

  final titles = <String, String>{};
  final taken = <String>{for (final name in ownNames) name.toLowerCase()};
  for (final album in shared) {
    final key = album.name.toLowerCase();
    var title = album.name;
    if (counts[key]! > 1) {
      final short = webIdLabel(album.ownerWebId);
      final who = owners[key]![short]!.length > 1
          ? webIdLongLabel(album.ownerWebId)
          : short;
      title = '${album.name} ($who)';
    }
    var unique = title;
    for (var n = 2; taken.contains(unique.toLowerCase()); n++) {
      unique = '$title $n';
    }
    taken.add(unique.toLowerCase());
    titles[album.url] = unique;
  }
  return titles;
}

/// How long what is shared with the user is trusted before it is read again.
/// Someone may share something at any moment, so every visit to a section
/// that shows shared items reads the log afresh once this has passed.

const Duration sharedRefreshAfter = Duration(seconds: 20);

/// Everything other people have shared with the user, read from the
/// permission log in the user's own Pod.
///
/// Nothing is copied: a shared photo stays in its owner's Pod and is read from
/// there, decrypted with the key its owner shared along with it. Revoked
/// access simply drops out the next time the log is read.

class SharedWithMe extends ChangeNotifier {
  List<MediaItem> _items = const [];
  List<SharedAlbum> _albums = const [];
  Map<String, PermissionLogLine> _lines = const {};
  DateTime? _readAt;
  Future<void>? _loading;
  String? _error;

  /// Every photo and video shared with the user.

  List<MediaItem> get items => _items;

  /// Every album shared with the user, in alphabetical order.

  List<SharedAlbum> get albums => _albums;

  /// What went wrong the last time the log was read, if anything.

  String? get error => _error;

  /// Read the permission log again, unless it was read within the last
  /// [sharedRefreshAfter] and [force] was not asked for. Callers arriving
  /// while a read is running wait for that read rather than starting another.

  Future<void> load({bool force = false}) {
    final running = _loading;
    if (running != null) return running;
    final readAt = _readAt;
    if (!force &&
        readAt != null &&
        DateTime.now().difference(readAt) < sharedRefreshAfter) {
      return Future<void>.value();
    }

    final load = _load().whenComplete(() => _loading = null);
    _loading = load;
    return load;
  }

  Future<void> _load() async {
    try {
      if (!await isUserLoggedIn()) return;
      final me = await getWebId();
      if (me == null) return;
      final dataDir = await getDataDirPath();

      final app = dataDir.split('/').first;
      final logUrl = await permissionLogUrl();

      final String content;
      try {
        content = utf8.decode(await getResource(logUrl));
      } on Object catch (e) {
        // A Pod that has never been shared anything may have no permission
        // log at all, which is nothing shared rather than a failure.

        debugPrint('PhotoPod: no permission log at $logUrl: $e');
        _items = const [];
        _albums = const [];
        _lines = const {};
        _error = null;
        _readAt = DateTime.now();
        return;
      }

      // The root of the user's own Pod, which is where the log is.

      final ownRoot = logUrl.substring(0, logUrl.indexOf('/$app/') + 1);

      final lines = latestLogLines(content);
      final sorted = sortSharedLog(lines, me: me, dataDir: dataDir);

      final items = <String, MediaItem>{
        for (final grant in sorted.media)
          if (ownPathOf(grant.url, ownRoot) == null)
            grant.url: _itemFor(grant.url, grant.owner),
      };

      final albums = <SharedAlbum>[];
      for (final grant in sorted.albums) {
        if (ownPathOf(grant.url, ownRoot) != null) continue;
        final album = await _readAlbum(
          grant.url,
          grant.owner,
          dataDir,
          ownRoot,
        );
        if (album == null) continue;
        albums.add(album);

        // Sharing an album shares what is in it, so its photos are shown
        // even where the log has no line of their own for them — but not one
        // whose own line is a revocation, which is also how a photo the user
        // has declined stays away while the album still lists it.

        // The user's own photos in it are held as Pod-relative paths, so
        // that the album shows them from the user's own Library instead.

        for (final url in album.itemUrls) {
          if (!url.contains('://')) continue;
          if (lines[url]?.type == 'revoke') continue;
          items.putIfAbsent(url, () => _itemFor(url, grant.owner));
        }
      }
      albums.sort(compareSharedAlbums);

      debugPrint(
        'PhotoPod: ${lines.length} resources in the permission log; '
        '${items.length} photos and videos and ${albums.length} albums are '
        'shared with you.',
      );

      _items = List.unmodifiable(
        items.values.where((item) => item.kind != null),
      );
      _albums = List.unmodifiable(albums);
      _lines = lines;
      _error = null;
      _readAt = DateTime.now();
    } on Object catch (e) {
      _error = '$e';
      debugPrint('PhotoPod: could not read what is shared with you: $e');
    } finally {
      notifyListeners();
    }
  }

  /// Stop [items], photos and videos someone else shared with the user,
  /// being shared with the user, and report the ones that could not be
  /// declined along with why.
  ///
  /// Only the owner can take the user out of a photo's ACL, so declining is
  /// done entirely in the user's own Pod: the key the owner shared to
  /// decrypt the photo is removed from the user's shared keys, and a
  /// revocation is added to the user's permission log, which from then on is
  /// the latest line for the photo and keeps it out of the Library, the
  /// albums and every other section. Should the owner share it again, their
  /// new grant is later still and the photo comes back.

  Future<Map<MediaItem, String>> decline(Iterable<MediaItem> items) async {
    final failed = <MediaItem, String>{};
    final declined = <String>{};

    final me = await getWebId();
    if (me == null) {
      for (final item in items) {
        failed[item] = 'You are not logged in.';
      }
      return failed;
    }

    for (final item in items) {
      if (!item.isShared) continue;
      try {
        await _declineUrl(item.url, item.sharedBy!, me);
        declined.add(item.url);
      } on Object catch (e) {
        failed[item] = '$e';
      }
    }

    _forget(declined);
    return failed;
  }

  /// Stop [album], an album someone else shared with the user, being shared
  /// with the user, along with the photos and videos in it that no other
  /// album still shared with the user holds.
  ///
  /// This is the recipient's side of what the owner's unsharing does: a
  /// photo goes with the album only when no other shared album keeps it, so
  /// declining one album never takes a photo out of another. Each is
  /// declined as [decline] declines a photo. Returns the URLs of the photos
  /// and videos that went, and what could not be declined, with why.

  Future<({List<String> gone, List<String> failed})> declineAlbum(
    SharedAlbum album,
  ) async {
    final me = await getWebId();
    if (me == null) {
      return (gone: <String>[], failed: ['You are not logged in.']);
    }

    final failed = <String>[];
    try {
      await _declineUrl(album.url, album.ownerWebId, me);
    } on Object catch (e) {
      // Should the album itself stay, its photos stay with it.

      return (gone: <String>[], failed: ['${album.name}: $e']);
    }

    final kept = {
      for (final other in _albums)
        if (other.url != album.url) ...other.itemUrls,
    };
    final declined = <String>{};
    for (final item in _items) {
      if (!album.itemUrls.contains(item.url) || kept.contains(item.url)) {
        continue;
      }
      try {
        await _declineUrl(item.url, item.sharedBy ?? album.ownerWebId, me);
        declined.add(item.url);
      } on Object catch (e) {
        failed.add('${item.name}: $e');
      }
    }

    _albums = List.unmodifiable(_albums.where((each) => each.url != album.url));
    _forget(declined);
    if (declined.isEmpty) {
      _readAt = null;
      notifyListeners();
    }
    return (gone: declined.toList(), failed: failed);
  }

  Future<void> _declineUrl(String url, String owner, String me) =>
      declineShare(url: url, owner: owner, me: me, line: _lines[url]);

  // Stop showing the photos and videos at [urls], which have just been
  // declined.

  void _forget(Set<String> urls) {
    if (urls.isEmpty) return;
    _items = List.unmodifiable(
      _items.where((item) => !urls.contains(item.url)),
    );

    // The log is read afresh next time rather than patched here, so that
    // what is shown always comes from the Pod.

    _readAt = null;
    notifyListeners();
  }

  // An album file is plain JSON listing Pod-relative paths in its owner's
  // Pod, so each path is turned into a URL against that Pod's root — except
  // for a photo that lies in the user's own Pod at [ownRoot], which is kept
  // as the Pod-relative path the user's own items carry. An album
  // that cannot be read — its owner may have deleted it without the log
  // catching up — is passed over rather than failing the rest.

  static Future<SharedAlbum?> _readAlbum(
    String url,
    String owner,
    String dataDir,
    String ownRoot,
  ) async {
    final root = podRootOf(url, dataDir);
    if (root == null) return null;
    try {
      final content = await readPod(url, pathType: PathType.absoluteUrl);
      return SharedAlbum(
        name: albumNameOf(url),
        url: url,
        ownerWebId: owner,
        itemUrls: {
          for (final path in decodeAlbum(content))
            _albumItem(path.contains('://') ? path : '$root$path', ownRoot),
        },
      );
    } on Object catch (e) {
      debugPrint('PhotoPod: could not read the shared album $url: $e');
      return null;
    }
  }

  static String _albumItem(String url, String ownRoot) =>
      ownPathOf(url, ownRoot) ?? url;

  static MediaItem _itemFor(String url, String owner) {
    final raw = url.substring(url.lastIndexOf('/') + 1);
    final stored = PodMediaService.decodeName(raw);
    return MediaItem(
      name: displayNameOf(stored),
      rawName: raw,
      path: url,
      url: url,
      isFolder: false,
      isEncrypted: stored.endsWith(encryptedSuffix),
      sharedBy: owner,
    );
  }
}
