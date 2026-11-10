/// The face inbox: where PhotoPod leaves photos for the Analyser.
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
        revokePermission,
        setInheritKeyDir,
        writePod;

import 'package:photopod/constants/face_analyser.dart';
import 'package:photopod/services/media_names.dart';
import 'package:photopod/services/pod_media_service.dart';

/// The folder, in PhotoPod's data folder, that is shared with the Analyser.
/// The leading full stop keeps it out of the album. It must match
/// `inbox.folder` in the analyser's configuration.

const String faceInboxFolderName = '.faces-inbox';

/// What each inbox file holds, inside its encryption.

const String faceRequestFormat = 'photopod-face-request';

/// The name a photo is known by in the inbox and in the Analyser's results:
/// the random part of its stored name, which says nothing about it, or, for
/// a photo stored before random names, a digest of its path.

String faceKeyOf(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  return randomKeyOf(name) ??
      sha256.convert(utf8.encode(path)).toString().substring(0, 32);
}

/// The face inbox in the user's own Pod.
///
/// Face recognition runs in the Analyser, a service beside the Solid server
/// with a Pod of its own ([FaceAnalyser.webId]), as HealthPod's blood
/// pressure analyser does. Turning People on makes `.faces-inbox/` in the
/// PhotoPod data folder and shares it with the Analyser, for reading and
/// writing, once. Every photo added is then left there as its large
/// rendition, encrypted with the folder's key ([leave]); the share is what
/// gives the Analyser that key. The Analyser reads each photo on the server,
/// shares what it found back to this Pod, and removes the photo from the
/// inbox, so a photo stays there only until it has been looked at.
///
/// Only the inbox is shared: the photos themselves, their small renditions
/// with the place they were taken, and everything else stay as private as
/// they were.

class FaceInbox {
  const FaceInbox._();

  // Whether the inbox is there, known for the Pod at [_knownFor] once asked.

  static bool? _enabled;
  static String? _knownFor;

  static Future<void> _queue = Future<void>.value();

  static final StreamController<void> _added =
      StreamController<void>.broadcast();

  /// Fires each time a photo is left in the inbox as it is added, so that
  /// [People] can ask the Analyser to look.

  static Stream<void> get added => _added.stream;

  /// The Pod-relative path of the inbox.

  static Future<String> path() async =>
      '${await PodMediaService.rootPath()}/$faceInboxFolderName';

  /// The URL of the inbox, with its trailing slash.

  static Future<String> url() async {
    final url = await PodMediaService.folderUrl(await path());
    return url.endsWith('/') ? url : '$url/';
  }

  /// Whether People has been turned on for this Pod, from any device: the
  /// inbox only exists once it has been shared.

  static Future<bool> isEnabled() async {
    final url = await FaceInbox.url();
    if (_knownFor == url && _enabled != null) return _enabled!;
    _enabled = await PodMediaService.folderExists(url);
    _knownFor = url;
    return _enabled!;
  }

  /// Make the inbox and share it with the Analyser.

  static Future<void> enable() async {
    final url = await FaceInbox.url();
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
      recipientWebIdList: [FaceAnalyser.webId],
      ownerWebId: webId,
      granterWebId: webId,
    );
    if (status != SolidFunctionCallStatus.success) {
      throw StateError(
        status == SolidFunctionCallStatus.notInitialised
            ? 'The Analyser Pod is not set up for PhotoPod yet.'
            : 'Could not share the face inbox with the Analyser ($status).',
      );
    }
    _enabled = true;
    _knownFor = url;
  }

  /// Stop sharing the inbox with the Analyser, and empty and remove it.
  /// What has been found already stays in the user's faces file.

  static Future<void> disable() async {
    final url = await FaceInbox.url();
    final webId = await getWebId();
    if (webId == null) throw StateError('Not logged in.');

    await revokePermission(
      fileName: url,
      isFile: false,
      isFileUrl: true,
      permissionList: [AccessMode.read.mode, AccessMode.write.mode],
      recipientIndOrGroupWebId: FaceAnalyser.webId,
      ownerWebId: webId,
      granterWebId: webId,
      recipientType: RecipientType.individual,
    );
    for (final key in await queued()) {
      await _delete('$url$key.enc.ttl');
    }
    await _delete('$url.acl');
    await _delete(url, ResourceContentType.directory);
    _enabled = false;
    _knownFor = url;
  }

  /// Leave the photo at [photoPath] in the inbox as [jpeg], its large
  /// rendition, for the Analyser to look at.

  static Future<void> leave(String photoPath, Uint8List jpeg) async {
    final inbox = await path();
    await writePod(
      '$inbox/${faceKeyOf(photoPath)}.enc.ttl',
      jsonEncode({
        'format': faceRequestFormat,
        'version': 1,
        'image': base64Encode(jpeg),
      }),
      pathType: PathType.relativeToPod,
      createAcl: false,
      overwrite: true,
      inheritKeyFrom: '$inbox/',
    );
  }

  /// Leave a photo just added, when People is on, and tell [added]. The
  /// photos of a batch are left one after another, behind the upload rather
  /// than holding it up. A failure is only logged: the next scan of People
  /// leaves the photo instead.

  static void photoAdded(String photoPath, Uint8List jpeg) {
    _queue = _queue.then((_) async {
      try {
        if (!await isEnabled()) return;
        await leave(photoPath, jpeg);
        _added.add(null);
      } on Object catch (e) {
        debugPrint('PhotoPod: could not leave $photoPath for the Analyser: $e');
      }
    });
  }

  /// The keys of the photos waiting in the inbox.

  static Future<Set<String>> queued() async {
    final listing = await getResourcesInContainer(await url());
    return {
      for (final file in listing.files)
        if (file.endsWith('.enc.ttl'))
          file
              .substring(file.lastIndexOf('/') + 1)
              .replaceFirst(RegExp(r'\.enc\.ttl$'), ''),
    };
  }

  /// Take the photos at [paths] out of the inbox, if they are still waiting
  /// there, as when they are deleted before the Analyser got to them.

  static Future<void> remove(Iterable<String> paths) async {
    if (!await isEnabled()) return;
    final url = await FaceInbox.url();
    final waiting = await queued();
    for (final key in paths.map(faceKeyOf).where(waiting.contains)) {
      await _delete('$url$key.enc.ttl');
    }
  }

  /// Forget what is known about the Pod, as on logout.

  static void reset() {
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
