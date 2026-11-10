/// Asking the Analyser to look at the face inbox, and reading what it found.
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart'
    show getTokensForResource, readExternalPod;

import 'package:photopod/constants/face_analyser.dart';
import 'package:photopod/models/face_book.dart';

/// Why the Analyser could not be used, worded for the user.

class FaceServiceException implements Exception {
  final String message;

  /// Whether logging in again might help.

  final bool unauthorised;

  /// Whether the face inbox is not shared with the Analyser, so People has
  /// to be turned on (again).

  final bool notShared;

  const FaceServiceException(
    this.message, {
    this.unauthorised = false,
    this.notShared = false,
  });

  @override
  String toString() => message;
}

/// What one run of the Analyser did.

class FaceAnalyserRun {
  /// Where the results for this Pod are published, shared with it.

  final String? resultUrl;

  /// How many photos this run looked at, and how many it could not read.

  final int analysed;
  final int failed;

  /// How many photos are still in the inbox, for the next run.

  final int pending;

  /// How many results are published and not yet taken by the app.

  final int waiting;

  const FaceAnalyserRun({
    this.resultUrl,
    this.analysed = 0,
    this.failed = 0,
    this.pending = 0,
    this.waiting = 0,
  });

  factory FaceAnalyserRun.fromJson(Map<String, dynamic> json) =>
      FaceAnalyserRun(
        resultUrl: json['result_url'] as String?,
        analysed: (json['analysed'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
        pending: (json['pending'] as num?)?.toInt() ?? 0,
        waiting: (json['waiting'] as num?)?.toInt() ?? 0,
      );
}

/// What the Analyser has published for this Pod: the faces in each photo,
/// by `faceKeyOf` key, and the photos it could not read.

class FaceAnalyserResults {
  final Map<String, List<FoundFace>> faces;
  final Map<String, String> failed;

  const FaceAnalyserResults(this.faces, this.failed);

  bool get isEmpty => faces.isEmpty && failed.isEmpty;

  /// Every key in the results, to acknowledge once they are filed.

  Iterable<String> get keys => {...faces.keys, ...failed.keys};

  /// The results [json] holds, or none when they were made with other
  /// models, whose embeddings mean nothing to the faces already found.

  factory FaceAnalyserResults.fromJson(Map<String, dynamic> json) {
    if (json['model'] != faceModelId) {
      return const FaceAnalyserResults({}, {});
    }
    final items = json['items'] as Map<String, dynamic>? ?? const {};
    final failed = json['failed'] as Map<String, dynamic>? ?? const {};
    return FaceAnalyserResults(
      {
        for (final entry in items.entries)
          entry.key: parseFoundFaces(
            (entry.value as Map<String, dynamic>)['faces'] as List? ?? const [],
          ),
      },
      {for (final entry in failed.entries) entry.key: '${entry.value}'},
    );
  }
}

/// The Analyser service, which finds the faces in the photos left in the
/// face inbox. See `FaceInbox` for how the photos get to it: through the
/// Pod, never through this.
///
/// [run] says "look now" and names, through the user's Solid login, the one
/// Pod to look at; the answer comes once the run is over. What it found is
/// then read with [readResults] from the Analyser's Pod, with the key the
/// Analyser shared into the user's, and filed in the user's own faces file.
/// The next [run] acknowledges what was filed, and the Analyser forgets it.

class FaceEngine {
  const FaceEngine._();

  /// How long one run may take: a few dozen photos.

  static const _timeout = Duration(minutes: 3);

  static http.Client? _client;

  /// Ask the Analyser to look at the face inbox now, after forgetting the
  /// results named in [ack].

  static Future<FaceAnalyserRun> run({Iterable<String> ack = const []}) async {
    final url = '${FaceAnalyser.serviceUrl}/v1/analyse';

    final ({String accessToken, String dPopToken}) tokens;
    try {
      tokens = await getTokensForResource(url, 'POST');
    } on Object {
      throw const FaceServiceException(
        'Log in to your Pod to find the people in your photos.',
        unauthorised: true,
      );
    }

    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse(url),
            headers: {
              'Authorization': 'DPoP ${tokens.accessToken}',
              'DPoP': tokens.dPopToken,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'ack': ack.toList()}),
          )
          .timeout(_timeout);
    } on Object catch (e) {
      throw FaceServiceException('Could not reach the Analyser ($e).');
    }

    final body = _decode(response.body);
    switch (response.statusCode) {
      case 200:
        return FaceAnalyserRun.fromJson(body);
      case 401:
        throw FaceServiceException(
          'The Analyser did not accept your login: ${body['error']}',
          unauthorised: true,
        );
      case 409:
        throw const FaceServiceException(
          'Your face inbox is not shared with the Analyser. Turn People on '
          'again.',
          notShared: true,
        );
      default:
        throw FaceServiceException(
          'The Analyser answered ${response.statusCode}'
          '${body['error'] == null ? '' : ': ${body['error']}'}',
        );
    }
  }

  /// The results published at [url]. A result just published can take a
  /// moment to be readable, so a failed read is tried again twice.

  static Future<FaceAnalyserResults> readResults(String url) async {
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final data = jsonDecode(await readExternalPod(url));
        if (data is Map<String, dynamic>) {
          return FaceAnalyserResults.fromJson(data);
        }
      } on Object catch (e) {
        last = e;
        debugPrint('PhotoPod: reading the faces found at $url: $e');
      }
    }
    throw FaceServiceException('Could not read what the Analyser found: $last');
  }

  /// Forget the connection, as on logout. It is made again when next needed.

  static void stop() {
    _client?.close();
    _client = null;
  }

  static http.Client get _http => _client ??= http.Client();

  static Map<String, dynamic> _decode(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) return data;
    } on FormatException {
      // Not JSON, as from a proxy's own error page.
    }
    return const {};
  }
}

/// The faces in [faces], as the Analyser lists them: `box` as fractions of
/// the photo's size, `score`, `embedding` as base64 of little-endian
/// float32, and `image` as a base64 JPEG.

List<FoundFace> parseFoundFaces(List<dynamic> faces) => [
  for (final face in faces.cast<Map<String, dynamic>>())
    (
      box: [for (final v in face['box'] as List) (v as num).toDouble()],
      score: (face['score'] as num).toDouble(),
      embedding: Float32List.view(
        Uint8List.fromList(base64Decode(face['embedding'] as String)).buffer,
      ),
      image: face['image'] == null
          ? null
          : base64Decode(face['image'] as String),
    ),
];
