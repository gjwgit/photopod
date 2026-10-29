/// Reading the permission log: what is shared with the user, and by whom.
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

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/albums.dart';
import 'package:photopod/models/favourites.dart';
import 'package:photopod/services/pod_media_service.dart';

/// Whether [url] is a PhotoPod album file inside the PhotoPod data folder
/// [dataDir] of some Pod: one of the files in the albums folder, or the list
/// of favourites.

bool isAlbumUrl(String url, String dataDir) {
  final albums = '/$dataDir/$albumsFolderName/';
  final at = url.indexOf(albums);
  if (at >= 0) {
    final rest = url.substring(at + albums.length);
    return !rest.contains('/') && albumNameOfFile(rest) != null;
  }
  return url.endsWith('/$dataDir/$favouritesFileName') ||
      url.endsWith('/$dataDir/${storedNameOf(favouritesFileName)}');
}

/// The name of the album whose file is at [url].

String albumNameOf(String url) {
  final raw = url.substring(url.lastIndexOf('/') + 1);
  if (displayNameOf(PodMediaService.decodeName(raw)) == favouritesFileName) {
    return favouritesAlbumName;
  }
  return albumNameOfFile(raw) ?? PodMediaService.decodeName(raw);
}

/// The URL of the root of the Pod that holds [url], found from where the
/// PhotoPod data folder [dataDir] starts, or null when [url] is not inside
/// one.

String? podRootOf(String url, String dataDir) {
  final at = url.indexOf('/$dataDir/');
  return at < 0 ? null : url.substring(0, at + 1);
}

/// The Pod-relative path of [url] when it lies inside the user's own Pod,
/// whose root is [ownRoot], or null when it is somewhere else.
///
/// Someone else's album may hold the user's own photos — the user shared a
/// photo with them and they put it in an album they share back. Such a photo
/// is the user's, read with the user's own key from the user's own Library,
/// and must never be taken for one shared with the user: solidpod would look
/// for a shared key that does not exist and the tile would stay blank.

String? ownPathOf(String url, String ownRoot) {
  if (ownRoot.isEmpty || url.length < ownRoot.length) return null;
  final head = url.substring(0, ownRoot.length);
  if (head.toLowerCase() != ownRoot.toLowerCase()) return null;
  return url.substring(ownRoot.length);
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
  String permissions,
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
      permissions: fields.length > 6 ? fields[6] : '',
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
