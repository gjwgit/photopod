/// Read and write media held in a Solid Pod.
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
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart';

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/container_listing.dart';

/// Raised when the Solid server refuses or fails a request. The message is
/// written for the user, since it is what the error dialogues display.

class PodMediaException implements Exception {
  /// What went wrong, in terms the user can act on.

  final String message;

  const PodMediaException(this.message);

  @override
  String toString() => message;
}

/// Reading and writing the photo and video files themselves.
///
/// Media is stored the way every Pod app in this family stores its data:
/// through solidpod's [writePod], which encrypts the content, wraps it in
/// Turtle and writes an accompanying `.acl`. A photo added as `beach.jpg`
/// becomes `beach.jpg.enc.ttl` on the server, and PhotoPod shows the name
/// without that suffix.
///
/// The alternative — writing the raw bytes under their own name — leaves the
/// files invisible to the shared file browsers, which list only `.ttl`
/// resources, and with no access control list to share through. Reading still
/// copes with a plain resource so that anything already in the album, or put
/// there by another tool, is not lost from view.

class PodMediaService {
  const PodMediaService._();

  /// The Pod-relative path of the folder PhotoPod browses, `photopod/data`.

  static Future<String> rootPath() async => getDataDirPath();

  /// The absolute URL of the container at Pod-relative [podPath].

  static Future<String> folderUrl(String podPath) async => getDirUrl(podPath);

  /// The folders and media files directly inside [podPath].
  ///
  /// When a [kind] is given, only files of that kind are returned, so the
  /// Photos section never shows videos and the Videos section never shows
  /// photos; pass null to list every file, as the recursive copy and move
  /// operations need to. Folders are always included, because a folder may
  /// hold either kind. Nothing from a subfolder is included; the user has to
  /// open it first.

  static Future<List<MediaItem>> listFolder(
    String podPath, {
    MediaKind? kind,
  }) async {
    final url = await folderUrl(podPath);
    final body = await _get(url, 'listing the folder');
    final entries = parseContainerListing(body);

    final items = <MediaItem>[];
    for (final entry in entries) {
      final isFolder = entry.isContainer || entry.rawName.endsWith('/');
      final raw = isFolder
          ? entry.rawName.substring(0, entry.rawName.length - 1)
          : entry.rawName;
      if (raw.isEmpty || raw.startsWith('.')) continue;

      // The server name carries the encryption suffix; the user never sees
      // it, and the extension that decides which section a file belongs to is
      // the one underneath.

      final storedName = decodeName(raw);
      final name = isFolder ? storedName : displayNameOf(storedName);
      if (!isFolder && kind != null && kindOf(name) != kind) continue;

      items.add(
        MediaItem(
          name: name,
          rawName: raw,
          path: '$podPath/$raw',
          url: '${_withSlash(url)}$raw${isFolder ? '/' : ''}',
          isFolder: isFolder,
          isEncrypted: !isFolder && storedName.endsWith(encryptedSuffix),
          modified: entry.modified,
          size: isFolder ? null : entry.size,
        ),
      );
    }
    return items;
  }

  /// The bytes of the photo or video [item] holds.
  ///
  /// An encrypted resource is read and decrypted through solidpod, which
  /// needs the security key to be available first, and its content is base64
  /// so that binary survives the Turtle envelope. A plain resource is fetched
  /// directly.

  static Future<Uint8List> readBytes(MediaItem item) async {
    if (!item.isEncrypted) return _readRaw(item.url);

    final content = await readPod(item.path, pathType: PathType.relativeToPod);

    try {
      return base64Decode(content.trim());
    } on FormatException {
      throw PodMediaException(
        'The contents of "${item.name}" are not in the format PhotoPod '
        'stores media in.',
      );
    }
  }

  /// Store [bytes] as a file called [displayName] inside [podPath].
  ///
  /// The file is encrypted and given an access control list, so it shows up
  /// in the shared file browsers and can be shared with another WebID. The
  /// caller must have secured the security key first, with SolidUI's
  /// `getKeyFromUserIfRequired`.

  static Future<void> writeMedia({
    required String podPath,
    required String displayName,
    required Uint8List bytes,
  }) async {
    final stored = storedNameOf(Uri.encodeComponent(displayName));
    await writePod(
      '$podPath/$stored',
      base64Encode(bytes),
      pathType: PathType.relativeToPod,
    );
  }

  /// Whether a file called [displayName] is already in [podPath], under
  /// either the encrypted name or a plain one.

  static Future<bool> mediaExists(String podPath, String displayName) async {
    final dirUrl = await folderUrl(podPath);
    final encoded = Uri.encodeComponent(displayName);
    return await fileExists('$dirUrl${storedNameOf(encoded)}') ||
        await fileExists('$dirUrl$encoded');
  }

  static Future<Uint8List> _readRaw(String url) async {
    final (:accessToken, :dPopToken) = await getTokensForResource(url, 'GET');
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Accept': '*/*',
        'Authorization': 'DPoP $accessToken',
        'DPoP': dPopToken,
      },
    );
    if (response.statusCode != 200) {
      throw PodMediaException(
        _describe(response.statusCode, 'reading the file'),
      );
    }
    return response.bodyBytes;
  }

  /// Whether a container exists at [url].

  static Future<bool> folderExists(String url) async =>
      await checkResourceStatus(_withSlash(url), isFile: false) ==
      ResourceStatus.exist;

  /// Whether a file exists at [url].

  static Future<bool> fileExists(String url) async =>
      await checkResourceStatus(url) == ResourceStatus.exist;

  /// Create the container at [url] if it is not already there.
  ///
  /// Some Solid servers create missing parent containers on a write and
  /// others do not, so PhotoPod always asks for the container explicitly
  /// before writing into it.

  static Future<void> ensureFolder(String url) async {
    final dirUrl = _withSlash(url);
    if (await folderExists(dirUrl)) return;
    await createDir(dirUrl);
  }

  /// Issue an authenticated GET and return the body, turning the server's
  /// status codes into messages the user can read.

  static Future<String> _get(String url, String action) async {
    final target = _withSlash(url);
    final (:accessToken, :dPopToken) = await getTokensForResource(
      target,
      'GET',
    );
    final response = await http.get(
      Uri.parse(target),
      headers: {
        'Accept': 'text/turtle',
        'Authorization': 'DPoP $accessToken',
        'DPoP': dPopToken,
      },
    );
    if (response.statusCode != 200) {
      throw PodMediaException(_describe(response.statusCode, action));
    }
    return response.body;
  }

  static String _describe(int status, String action) => switch (status) {
    401 || 403 => 'You do not have permission for $action on this Pod.',
    404 => 'The resource was not found while $action.',
    _ => 'The server returned status $status while $action.',
  };

  static String _withSlash(String url) => url.endsWith('/') ? url : '$url/';

  /// The readable form of a resource name the server spells with
  /// percent-escapes, so `my%20photo.jpg` is shown as `my photo.jpg`. A name
  /// that is not valid escaping is left exactly as it came.

  static String decodeName(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } on FormatException {
      return raw;
    }
  }
}
