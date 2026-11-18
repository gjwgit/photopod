/// Write an encrypted resource to the Pod, trying again when the connection
/// or the server lets the write down part way.
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

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart'
    show
        AccessForbiddenException,
        KeyManager,
        NotLoggedInException,
        PathType,
        ResourceStatus,
        checkResourceStatus,
        getFileUrl,
        writePod;

/// How many times a write is attempted before giving up.

const int writeAttempts = 3;

/// How long to wait before writing again; the wait grows with each attempt.

const Duration writeRetryPause = Duration(seconds: 2);

/// Whether [error], raised by a write to the Pod, may well not happen again
/// if the write is simply repeated.
///
/// A photo straight off a phone's camera is several megabytes, and grows by
/// more than half again once encrypted and wrapped in Turtle, so an upload of
/// one over a mobile connection is easily interrupted. When that happens the
/// HTTP client solidpod uses sends the request a second time, but with the
/// very same DPoP proof, and the Solid server rejects a proof it has already
/// seen. solidpod reports that, and any other status it does not single out,
/// as "Failed to create resource!". A fresh call to [writePod] signs a fresh
/// proof, so it is worth trying again, as it is after a dropped connection or
/// a request that timed out.
///
/// A refusal of permission, a session that has ended, or a file that is
/// already there will not change on a second attempt, and is passed on at
/// once.

bool isTransientWriteError(Object error) {
  if (error is AccessForbiddenException || error is NotLoggedInException) {
    return false;
  }
  if (error is http.ClientException || error is TimeoutException) return true;
  final text = '$error';
  return text.contains('Failed to create resource') ||
      text.contains('Unable to determine if file') ||
      text.contains('Connection closed') ||
      text.contains('Connection reset') ||
      text.contains('Broken pipe');
}

/// Run [write], once for each attempt, until it succeeds or fails in a way
/// [isTransientWriteError] says will not mend.
///
/// [write] is told which attempt it is, counting from one. [beforeRetry], if
/// given, runs before each attempt after the first, to tidy up whatever the
/// failed attempt left behind; if it fails in turn, that is logged and the
/// next attempt goes ahead regardless. The error from the last attempt is
/// the one passed on.

@visibleForTesting
Future<void> retryWrite(
  Future<void> Function(int attempt) write, {
  Future<void> Function()? beforeRetry,
  int attempts = writeAttempts,
  Duration pause = writeRetryPause,
  String what = 'a resource',
}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      if (attempt > 1 && beforeRetry != null) {
        try {
          await beforeRetry();
        } on Object catch (e) {
          debugPrint('PhotoPod: could not tidy up before writing $what: $e');
        }
      }
      await write(attempt);
      return;
    } on Object catch (e) {
      if (attempt >= attempts || !isTransientWriteError(e)) rethrow;
      debugPrint(
        'PhotoPod: writing $what failed ($e); '
        'trying again (attempt ${attempt + 1} of $attempts).',
      );
      await Future<void>.delayed(pause * attempt);
    }
  }
}

/// Write [content] to the Pod-relative [path] through solidpod's [writePod],
/// trying again, up to [writeAttempts] times in all, when the write fails in
/// a way that may not happen twice.
///
/// [overwrite] says whether a file already at [path] may be replaced. When it
/// may not, the path is looked at first, and only if nothing is there do the
/// attempts after the first overwrite, since the one before may have left
/// part of the file behind. A file that was there all along is never
/// replaced.
///
/// A resource that had no individual key of its own is given one by the
/// first attempt. solidpod holds that key in memory before it saves the key
/// file, so if the save is what failed, a second attempt would find the key,
/// encrypt with it, and never save it, and the file could not be read in the
/// next session. The key is therefore dropped before trying again, which
/// saves the key file, and the attempt makes a new key and saves it once
/// more. A resource encrypted under its folder's key, [inheritKeyFrom], has
/// no key of its own to look after.

Future<void> writePodRetrying(
  String path,
  String content, {
  bool overwrite = false,
  bool createAcl = true,
  String? inheritKeyFrom,
}) async {
  final url = await getFileUrl(path);
  final hadKey =
      inheritKeyFrom != null || await KeyManager.hasIndividualKey(url);
  final wasFree =
      !overwrite &&
      await checkResourceStatus(url, useHead: true) == ResourceStatus.notExist;

  await retryWrite(
    (attempt) => writePod(
      path,
      content,
      overwrite: overwrite || (wasFree && attempt > 1),
      createAcl: createAcl,
      inheritKeyFrom: inheritKeyFrom,
      pathType: PathType.relativeToPod,
    ),
    beforeRetry: hadKey
        ? null
        : () => KeyManager.removeIndividualKey(resourcePath: path),
    what: path,
  );
}
