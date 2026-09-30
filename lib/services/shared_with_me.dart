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
        getFileUrl,
        getResource,
        getWebId,
        isUserLoggedIn,
        readPod;

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/albums.dart';
import 'package:photopod/models/favourites.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/pod_media_service.dart';

/// An album someone else has shared with the user.

class SharedAlbum {
  /// The album's name as its owner gave it.

  final String name;

  /// The URL of the album file in the owner's Pod, which is also what tells
  /// two shared albums of the same name apart.

  final String url;

  /// The WebID of the album's owner.

  final String ownerWebId;

  /// The URLs of the photos and videos the album holds.

  final Set<String> itemUrls;

  const SharedAlbum({
    required this.name,
    required this.url,
    required this.ownerWebId,
    required this.itemUrls,
  });
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

/// Whether [url] is a PhotoPod album file inside the PhotoPod data folder
/// [dataDir] of some Pod: one of the files in the albums folder, or the list
/// of favourites.

bool isAlbumUrl(String url, String dataDir) {
  final albums = '/$dataDir/$albumsFolderName/';
  final at = url.indexOf(albums);
  if (at >= 0) {
    final rest = url.substring(at + albums.length);
    return rest.isNotEmpty &&
        !rest.contains('/') &&
        rest.endsWith(albumFileExtension);
  }
  return url.endsWith('/$dataDir/$favouritesFileName');
}

/// The name of the album whose file is at [url].

String albumNameOf(String url) {
  final file = PodMediaService.decodeName(
    url.substring(url.lastIndexOf('/') + 1),
  );
  if (file == favouritesFileName) return favouritesAlbumName;
  return file.endsWith(albumFileExtension)
      ? file.substring(0, file.length - albumFileExtension.length)
      : file;
}

/// The URL of the root of the Pod that holds [url], found from where the
/// PhotoPod data folder [dataDir] starts, or null when [url] is not inside
/// one.

String? podRootOf(String url, String dataDir) {
  final at = url.indexOf('/$dataDir/');
  return at < 0 ? null : url.substring(0, at + 1);
}

/// One line of a permission log: who gave whom what access to which
/// resource, and when.

typedef PermissionLogLine = ({
  String time,
  String url,
  String owner,
  String type,
  String granter,
  String recipient,
});

/// A shared resource that has survived the permission log: its URL and its
/// owner.

typedef SharedGrant = ({String url, String owner});

// A log line as solidpod writes it: a time stamp such as `20260930T101010`
// followed by the other fields, separated by semicolons, held in a string
// literal and usually wrapped in angle brackets.

final RegExp _logLine = RegExp(r'"<?(\d{8}T\d{6}[^"]*?)>?"');

/// Every line of the permission log [content], latest first for each
/// resource: the latest line for a resource is the one that decides whether
/// it is still shared.
///
/// The log is read directly rather than through solidpod's own reader, which
/// keeps only the lines naming the user's WebID exactly as the login spells
/// it — a WebID typed by the sharer with or without its `#me`, or in a
/// different case, would silently drop out — and which gives up on the
/// whole log over a single damaged line.

Map<String, PermissionLogLine> latestLogLines(String content) {
  final latest = <String, PermissionLogLine>{};
  for (final match in _logLine.allMatches(content)) {
    final fields = match.group(1)!.split(';');
    if (fields.length < 6) continue;
    final line = (
      time: fields[0],
      url: fields[1],
      owner: fields[2],
      type: fields[3].toLowerCase(),
      granter: fields[4],
      recipient: fields[5],
    );
    final before = latest[line.url];
    if (before == null || line.time.compareTo(before.time) >= 0) {
      latest[line.url] = line;
    }
  }
  return latest;
}

/// [webId] in a form in which two spellings of the same WebID agree: without
/// its fragment or a trailing slash, and with the host in lower case.

String sameWebId(String webId) {
  var plain = webId.trim();
  final hash = plain.indexOf('#');
  if (hash >= 0) plain = plain.substring(0, hash);
  while (plain.endsWith('/')) {
    plain = plain.substring(0, plain.length - 1);
  }
  final uri = Uri.tryParse(plain);
  return uri == null || uri.host.isEmpty
      ? plain
      : uri.replace(host: uri.host.toLowerCase()).toString();
}

/// The photos, videos and albums still shared with [me] according to the
/// latest [lines] of the permission log, sorted into the two kinds, and
/// leaving out anything that is not PhotoPod's.
///
/// solidpod appends a line to the recipient's permission log for every grant
/// and every revocation, so a resource whose latest line is a revocation is
/// no longer shared. Lines in which the user is the owner or the one who
/// granted the access record the user's own sharing, not sharing with them.

({List<SharedGrant> media, List<SharedGrant> albums}) sortSharedLog(
  Map<String, PermissionLogLine> lines, {
  required String me,
  required String dataDir,
}) {
  final media = <SharedGrant>[];
  final albums = <SharedGrant>[];
  final self = sameWebId(me);

  for (final line in lines.values) {
    if (line.type != 'grant') continue;
    if (sameWebId(line.owner) == self || sameWebId(line.granter) == self) {
      continue;
    }
    final url = line.url;
    if (!url.contains('/$dataDir/')) continue;

    if (isAlbumUrl(url, dataDir)) {
      albums.add((url: url, owner: line.owner));
      continue;
    }
    final raw = url.substring(url.lastIndexOf('/') + 1);
    final name = displayNameOf(PodMediaService.decodeName(raw));
    if (raw.isNotEmpty && kindOf(name) != null) {
      media.add((url: url, owner: line.owner));
    }
  }
  return (media: media, albums: albums);
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

      // The log sits beside the data folder, in the app's own logs folder.

      final app = dataDir.split('/').first;
      final logUrl = await getFileUrl('$app/logs/permissions-log.ttl');

      final String content;
      try {
        content = utf8.decode(await getResource(logUrl));
      } on Object catch (e) {
        // A Pod that has never been shared anything may have no permission
        // log at all, which is nothing shared rather than a failure.

        debugPrint('PhotoPod: no permission log at $logUrl: $e');
        _items = const [];
        _albums = const [];
        _error = null;
        _readAt = DateTime.now();
        return;
      }

      final lines = latestLogLines(content);
      final sorted = sortSharedLog(lines, me: me, dataDir: dataDir);

      final items = <String, MediaItem>{
        for (final grant in sorted.media)
          grant.url: _itemFor(grant.url, grant.owner),
      };

      final albums = <SharedAlbum>[];
      for (final grant in sorted.albums) {
        final album = await _readAlbum(grant.url, grant.owner, dataDir);
        if (album == null) continue;
        albums.add(album);

        // Sharing an album shares what is in it, so its photos are shown
        // even where the log has no line of their own for them.

        for (final url in album.itemUrls) {
          items.putIfAbsent(url, () => _itemFor(url, grant.owner));
        }
      }
      albums.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      debugPrint(
        'PhotoPod: ${lines.length} resources in the permission log; '
        '${items.length} photos and videos and ${albums.length} albums are '
        'shared with you.',
      );

      _items = List.unmodifiable(
        items.values.where((item) => item.kind != null),
      );
      _albums = List.unmodifiable(albums);
      _error = null;
      _readAt = DateTime.now();
    } on Object catch (e) {
      _error = '$e';
      debugPrint('PhotoPod: could not read what is shared with you: $e');
    } finally {
      notifyListeners();
    }
  }

  // An album file is plain JSON listing Pod-relative paths in its owner's
  // Pod, so each path is turned into a URL against that Pod's root. An album
  // that cannot be read — its owner may have deleted it without the log
  // catching up — is passed over rather than failing the rest.

  static Future<SharedAlbum?> _readAlbum(
    String url,
    String owner,
    String dataDir,
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
            path.contains('://') ? path : '$root$path',
        },
      );
    } on Object catch (e) {
      debugPrint('PhotoPod: could not read the shared album $url: $e');
      return null;
    }
  }

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
