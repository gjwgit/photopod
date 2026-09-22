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
/// PhotoPod stores media as ordinary binary resources under `photopod/data/`,
/// keeping each file's own name and content type, rather than wrapping them
/// in solidpod's encrypted Turtle envelope. That keeps an album readable by
/// any other Solid client, lets a shared photo be opened directly from its
/// URL, and is what makes thumbnails and video playback possible at all.

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

      final name = decodeName(raw);
      if (!isFolder && kind != null && kindOf(name) != kind) continue;

      items.add(
        MediaItem(
          name: name,
          rawName: raw,
          path: '$podPath/$raw',
          url: '${_withSlash(url)}$raw${isFolder ? '/' : ''}',
          isFolder: isFolder,
          modified: entry.modified,
          size: isFolder ? null : entry.size,
        ),
      );
    }
    return items;
  }

  /// The bytes of the resource at [url].

  static Future<Uint8List> readBytes(String url) async {
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

  /// Store [bytes] at [url], replacing whatever is there.
  ///
  /// The content type is taken from the file name so the server records the
  /// media type rather than a generic binary blob.

  static Future<void> writeBytes(
    String url,
    Uint8List bytes,
    String fileName,
  ) async {
    final (:accessToken, :dPopToken) = await getTokensForResource(url, 'PUT');
    final response = await http.put(
      Uri.parse(url),
      headers: {
        'Accept': '*/*',
        'Authorization': 'DPoP $accessToken',
        'Content-Type': contentTypeOf(fileName),
        'DPoP': dPopToken,
      },
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PodMediaException(
        _describe(response.statusCode, 'saving the file'),
      );
    }
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
