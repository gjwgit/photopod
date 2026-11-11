/// The inboxes: the folders where PhotoPod leaves photos for the Analyser.
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

import 'package:crypto/crypto.dart';
import 'package:solidpod/solidpod.dart'
    show
        AccessMode,
        PathType,
        RecipientType,
        ResourceContentType,
        SolidFunctionCallStatus,
        deleteResource,
        getResourcesInContainer,
        getWebId,
        grantPermission,
        readPod,
        revokePermission,
        setInheritKeyDir,
        writePod;

import 'package:photopod/constants/analyser.dart';
import 'package:photopod/services/media_names.dart';
import 'package:photopod/services/pod_media_service.dart';

/// The end of the name of a photo left in an inbox.

const String _photoSuffix = '.enc.ttl';

/// What an inbox holds: the photos still waiting for the Analyser, and the
/// answers it has written, each by [inboxKeyOf] key.

typedef InboxListing = ({Set<String> waiting, Set<String> answered});

/// The name a photo is known by in an inbox and in the Analyser's answers:
/// the random part of its stored name, which says nothing about it, or, for
/// a photo stored before random names, a digest of its path.

String inboxKeyOf(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  return randomKeyOf(name) ??
      sha256.convert(utf8.encode(path)).toString().substring(0, 32);
}

/// The face inbox, which People shares. Its folder must match `inbox.folder`
/// in the analyser's configuration.

final AnalyserInbox faceInbox = AnalyserInbox(
  folderName: '.faces-inbox',
  requestFormat: 'photopod-face-request',
  resultSuffix: '.faces.enc.ttl',
  label: 'face inbox',
);

/// The tag inbox, which Tags shares. Its folder must match `tags.folder` in
/// the analyser's configuration.

final AnalyserInbox tagInbox = AnalyserInbox(
  folderName: '.tags-inbox',
  requestFormat: 'photopod-tag-request',
  resultSuffix: '.tags.enc.ttl',
  label: 'tag inbox',
);

/// Leave a photo just added in every inbox that is on, for People and Tags
/// alike ([AnalyserInbox.photoAdded]).

void photoAdded(String photoPath, Uint8List jpeg) {
  faceInbox.photoAdded(photoPath, jpeg);
  tagInbox.photoAdded(photoPath, jpeg);
}

/// One inbox in the user's own Pod.
///
/// The work is done by the Analyser, a service with a Pod of its own
/// ([Analyser.webId]), as HealthPod's blood pressure analyser is. PhotoPod
/// never talks to the service: the two Pods share a folder, and the Analyser
/// does the rest.
///
/// Turning the inbox on makes its folder in the PhotoPod data folder and
/// shares it with the Analyser, for reading and writing, once. Every photo
/// added is then left there as its large rendition, `<key>.enc.ttl`,
/// encrypted with the folder's key ([leave]); the share is what gives the
/// Analyser that key. The Analyser, which looks at every shared inbox every
/// few seconds, reads the photo, writes what it found beside it as
/// `<key><resultSuffix>`, encrypted with the same key, and removes the
/// photo. PhotoPod files each answer and deletes it ([readAnswer],
/// [deleteAnswer]).
///
/// Each inbox is shared on its own, so People and Tags are turned on and off
/// separately. Only the inbox is shared: the photos themselves, their small
/// renditions with the place they were taken, and everything else stay as
/// private as they were.

class AnalyserInbox {
  AnalyserInbox({
    required this.folderName,
    required this.requestFormat,
    required this.resultSuffix,
    required this.label,
  });

  /// The folder, in PhotoPod's data folder, that is shared with the
  /// Analyser. The leading full stop keeps it out of the album.

  final String folderName;

  /// What each photo left in the inbox holds, inside its encryption.

  final String requestFormat;

  /// The end of the name of the answer the Analyser writes beside a photo.

  final String resultSuffix;

  /// What the inbox is called in messages.

  final String label;

  // Whether the inbox is there, known for the Pod at [_knownFor] once asked.

  bool? _enabled;
  String? _knownFor;

  Future<void> _queue = Future<void>.value();

  final StreamController<void> _added = StreamController<void>.broadcast();

  /// Fires each time a photo is left in the inbox as it is added, so that
  /// the section waiting on it can look out for the answer.

  Stream<void> get added => _added.stream;

  /// The Pod-relative path of the inbox.

  Future<String> path() async =>
      '${await PodMediaService.rootPath()}/$folderName';

  /// The URL of the inbox, with its trailing slash.

  Future<String> url() async {
    final url = await PodMediaService.folderUrl(await path());
    return url.endsWith('/') ? url : '$url/';
  }

  /// Whether the inbox has been turned on for this Pod, from any device: it
  /// only exists once it has been shared.

  Future<bool> isEnabled() async {
    final url = await this.url();
    if (_knownFor == url && _enabled != null) return _enabled!;
    _enabled = await PodMediaService.folderExists(url);
    _knownFor = url;
    return _enabled!;
  }

  /// Make the inbox and share it with the Analyser.

  Future<void> enable() async {
    final url = await this.url();
    final webId = await getWebId();
    if (webId == null) throw StateError('Not logged in.');

    // The folder key has to exist before the folder is shared, or the share
    // carries no key and the Analyser can read nothing left there.

    await setInheritKeyDir(url);

    // grantPermission() declares the list as dynamic but reads each entry
    // as a String, so the mode names are what must be passed.

    final status = await grantPermission(
      fileName: url,
      isFile: false,
      permissionList: [AccessMode.read.mode, AccessMode.write.mode],
      recipientType: RecipientType.individual,
      recipientWebIdList: [Analyser.webId],
      ownerWebId: webId,
      granterWebId: webId,
    );
    if (status != SolidFunctionCallStatus.success) {
      throw StateError(
        status == SolidFunctionCallStatus.notInitialised
            ? 'The Analyser Pod is not set up for PhotoPod yet.'
            : 'Could not share the $label with the Analyser ($status).',
      );
    }
    _enabled = true;
    _knownFor = url;
  }

  /// Stop sharing the inbox with the Analyser, and empty and remove it.
  /// What has been found already stays where it was filed.

  Future<void> disable() async {
    final url = await this.url();
    final webId = await getWebId();
    if (webId == null) throw StateError('Not logged in.');

    await revokePermission(
      fileName: url,
      isFile: false,
      isFileUrl: true,
      permissionList: [AccessMode.read.mode, AccessMode.write.mode],
      recipientIndOrGroupWebId: Analyser.webId,
      ownerWebId: webId,
      granterWebId: webId,
      recipientType: RecipientType.individual,
    );
    final listing = await list();
    for (final key in listing.waiting) {
      await _delete('$url$key$_photoSuffix');
    }
    for (final key in listing.answered) {
      await _delete('$url$key$resultSuffix');
    }
    await _delete('$url.acl');
    await _delete(url, ResourceContentType.directory);
    _enabled = false;
    _knownFor = url;
  }

  /// Leave the photo at [photoPath] in the inbox as [jpeg], its large
  /// rendition, for the Analyser to look at.

  Future<void> leave(String photoPath, Uint8List jpeg) async {
    final inbox = await path();
    await writePod(
      '$inbox/${inboxKeyOf(photoPath)}$_photoSuffix',
      jsonEncode({
        'format': requestFormat,
        'version': 1,
        'image': base64Encode(jpeg),
      }),
      pathType: PathType.relativeToPod,
      createAcl: false,
      overwrite: true,
      inheritKeyFrom: '$inbox/',
    );
  }

  /// Leave a photo just added, when the inbox is on, and tell [added]. The
  /// photos of a batch are left one after another, behind the upload rather
  /// than holding it up. A failure is only logged: the next scan leaves the
  /// photo instead.

  void photoAdded(String photoPath, Uint8List jpeg) {
    _queue = _queue.then((_) async {
      try {
        if (!await isEnabled()) return;
        await leave(photoPath, jpeg);
        _added.add(null);
      } on Object catch (e) {
        debugPrint('PhotoPod: could not leave $photoPath in the $label: $e');
      }
    });
  }

  /// What the inbox holds.

  Future<InboxListing> list() async {
    final listing = await getResourcesInContainer(await url());
    final waiting = <String>{};
    final answered = <String>{};
    for (final file in listing.files) {
      final name = file.substring(file.lastIndexOf('/') + 1);
      if (name.endsWith(resultSuffix)) {
        answered.add(name.substring(0, name.length - resultSuffix.length));
      } else if (name.endsWith(_photoSuffix)) {
        final key = name.substring(0, name.length - _photoSuffix.length);

        // An answer of another kind is never left here, but would not be a
        // photo either.

        if (!key.contains('.')) waiting.add(key);
      }
    }
    return (waiting: waiting, answered: answered);
  }

  /// The Analyser's answer for the photo known by [key], decrypted.

  Future<String> readAnswer(String key) async => readPod(
    '${await path()}/$key$resultSuffix',
    pathType: PathType.relativeToPod,
  );

  /// Delete the answer for [key], once it is filed.

  Future<void> deleteAnswer(String key) async =>
      _delete('${await url()}$key$resultSuffix');

  /// Take the photos at [paths] out of the inbox, and any answers for them,
  /// as when they are deleted before the Analyser or the app got to them.

  Future<void> remove(Iterable<String> paths) async {
    if (!await isEnabled()) return;
    final url = await this.url();
    final listing = await list();
    for (final key in paths.map(inboxKeyOf)) {
      if (listing.waiting.contains(key)) {
        await _delete('$url$key$_photoSuffix');
      }
      if (listing.answered.contains(key)) {
        await _delete('$url$key$resultSuffix');
      }
    }
  }

  /// Forget what is known about the Pod, as on logout.

  void reset() {
    _enabled = null;
    _knownFor = null;
  }

  static Future<void> _delete(
    String url, [
    ResourceContentType type = ResourceContentType.any,
  ]) async {
    try {
      await deleteResource(url, type);
    } on Object catch (e) {
      // Usually not there to delete, which is fine.
      debugPrint('PhotoPod: $url not removed: $e');
    }
  }
}
