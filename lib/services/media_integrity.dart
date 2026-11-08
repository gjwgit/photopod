/// Telling a photo stored whole from one the server kept only part of.
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
/// Authors: Graham Williams

library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart' show getTokensForResource;

import 'package:photopod/services/pod_media_service.dart';

/// How much of the end of a stored file is fetched to see that it is whole.

const int _tailBytes = 64;

/// Whether [content], as a Solid server returned it, is Turtle that stops
/// part way through.
///
/// Every file PhotoPod stores is Turtle, and a complete Turtle file ends
/// with the full stop that closes its last statement. A server that loses
/// the connection part way through an upload has been seen to keep what
/// arrived, which then ends in the middle of the encrypted photo.

bool isCutShort(String content) {
  final text = content.trimLeft();
  if (!text.startsWith('@prefix') && !text.startsWith('<')) return false;
  return !_endsWhole(text);
}

bool _endsWhole(String text) => text.trimRight().endsWith('.');

/// Raised when a photo or video is incomplete on the Pod, so that no number
/// of attempts will read it, and only adding it again will mend it.

class IncompleteMediaException extends PodMediaException {
  IncompleteMediaException(String name)
    : super(
        '"$name" is incomplete on your Pod: the server kept only part of it '
        'when it was added, and it cannot be opened. Delete it and add it '
        'again from the original.',
      );
}

/// Checking that what was written to the Pod arrived whole.

class MediaIntegrity {
  const MediaIntegrity._();

  /// Whether the file at [url] ends as a whole Turtle file does, read from
  /// its last few bytes alone. Null when the server would send the whole
  /// file to answer, and so is not asked.

  static Future<bool?> endsWhole(String url) async {
    final (:accessToken, :dPopToken) = await getTokensForResource(url, 'GET');
    final request = http.Request('GET', Uri.parse(url))
      ..headers.addAll({
        'Accept': '*/*',
        'Authorization': 'DPoP $accessToken',
        'DPoP': dPopToken,
        'Range': 'bytes=-$_tailBytes',
      });

    final client = http.Client();
    try {
      final response = await client.send(request);
      if (response.statusCode != 206) {
        // The server is sending the whole file, or refused: either way, it
        // cannot answer cheaply.

        unawaited(response.stream.listen(null).cancel());
        return null;
      }
      final tail = await response.stream.bytesToString(
        const Utf8Codec(allowMalformed: true),
      );
      return _endsWhole(tail);
    } finally {
      client.close();
    }
  }
}
