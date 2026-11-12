/// The inboxes: where PhotoPod leaves photos for the Analyser.
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
import 'dart:typed_data';

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

/// What the Analyser writes in an inbox once it has answered every photo
/// in it. It must match `DONE_NAME` in the analyser's inbox.py.

const String _doneName = 'done';

/// What an inbox holds: the photos still waiting for the Analyser, and the
/// answers it has written, each by [inboxKeyOf] key, and whether it has
/// answered them all.

typedef InboxListing = ({Set<String> waiting, Set<String> answered, bool done});

/// The name a photo is known by in an inbox and in the Analyser's answers:
/// the random part of its stored name, which says nothing about it, or, for
/// a photo stored before random names, a digest of its path.

String inboxKeyOf(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  return randomKeyOf(name) ??
      sha256.convert(utf8.encode(path)).toString().substring(0, 32);
}

/// [picture], a JPEG or PNG, without what it says about itself beyond the
/// picture: the EXIF block, which says where and when it was taken and with
/// what, XMP, IPTC and any comments. Everything needed to show it, colour
/// profile included, is kept. Null when [picture] is neither, or is not
/// well formed, so that nothing is let through unexamined.
///
/// Byte by byte rather than decoded and encoded again, which would cost far
/// more and change the picture: only whole segments, or chunks, are dropped.

Uint8List? withoutMetadata(Uint8List picture) {
  if (_startsWith(picture, _jpegStart)) return _jpegWithoutMetadata(picture);
  if (_startsWith(picture, _pngStart)) return _pngWithoutMetadata(picture);
  return null;
}

const _jpegStart = [0xff, 0xd8];
const _pngStart = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

bool _startsWith(Uint8List bytes, List<int> start) {
  if (bytes.length < start.length) return false;
  for (var i = 0; i < start.length; i++) {
    if (bytes[i] != start[i]) return false;
  }
  return true;
}

// A JPEG is a run of segments, each a marker and its length, up to the
// start of the scan, after which comes the picture itself. APP1 holds EXIF
// and XMP, APP13 IPTC, and COM comments.

Uint8List? _jpegWithoutMetadata(Uint8List bytes) {
  const app1 = 0xe1, app13 = 0xed, comment = 0xfe, startOfScan = 0xda;
  final out = BytesBuilder(copy: false)..add(bytes.sublist(0, 2));
  var at = 2;
  while (at + 4 <= bytes.length) {
    if (bytes[at] != 0xff) return null;
    final marker = bytes[at + 1];
    if (marker == 0xff) {
      at++;
      continue;
    }
    if (marker == startOfScan) {
      out.add(bytes.sublist(at));
      return out.takeBytes();
    }
    final end = at + 2 + ((bytes[at + 2] << 8) | bytes[at + 3]);
    if (end < at + 4 || end > bytes.length) return null;
    if (marker != app1 && marker != app13 && marker != comment) {
      out.add(bytes.sublist(at, end));
    }
    at = end;
  }
  return null;
}

// A PNG is a run of chunks, each its length, its type, its data and a
// checksum of its own, so a chunk can be dropped whole.

Uint8List? _pngWithoutMetadata(Uint8List bytes) {
  const dropped = {'eXIf', 'tEXt', 'zTXt', 'iTXt'};
  final out = BytesBuilder(copy: false)..add(bytes.sublist(0, 8));
  var at = 8;
  while (at + 12 <= bytes.length) {
    final length = ByteData.sublistView(bytes, at, at + 4).getUint32(0);
    final end = at + 12 + length;
    if (end > bytes.length) return null;
    final type = String.fromCharCodes(bytes.sublist(at + 4, at + 8));
    if (!dropped.contains(type)) out.add(bytes.sublist(at, end));
    at = end;
    if (type == 'IEND') return out.takeBytes();
  }
  return null;
}

/// The face inbox, which Identify People shares. Its folder must match
/// `inbox.folder` in the analyser's configuration.

final AnalyserInbox faceInbox = AnalyserInbox(
  folderName: '.faces-inbox',
  requestFormat: 'photopod-face-request',
  resultSuffix: '.faces.enc.ttl',
  label: 'face inbox',
);

/// The tag inbox, which Tag Photos shares. Its folder must match
/// `tags.folder` in the analyser's configuration.

final AnalyserInbox tagInbox = AnalyserInbox(
  folderName: '.tags-inbox',
  requestFormat: 'photopod-tag-request',
  resultSuffix: '.tags.enc.ttl',
  label: 'tag inbox',
);

/// One inbox in the user's own Pod.
///
/// The work is done by the Analyser, a service with a Pod of its own
/// ([Analyser.webId]), as HealthPod's blood pressure analyser is. PhotoPod
/// never talks to the service: the two Pods share a folder, and the Analyser
/// does the rest.
///
/// The inbox is there only while the user is having photos looked at. Each
/// time the user asks, with Identify People or Tag Photos, [prepare] makes
/// the inbox's folder in the PhotoPod data folder, the photos chosen are
/// left there as their large renditions, `<key>.enc.ttl`, encrypted with the
/// folder's key ([leave]), and [request] then shares the folder with the
/// Analyser, for reading and writing: the share is what gives the Analyser
/// that key, and the server tells the Analyser of it at once. The Analyser
/// reads each photo, writes what it found beside it as
/// `<key><resultSuffix>`, encrypted with the same key, removes the photo,
/// and writes `done` when all are answered. PhotoPod files each answer and
/// deletes it ([readAnswer], [deleteAnswer]), and [close] then ends the
/// share and removes the inbox.
///
/// Each inbox is shared on its own, and only for as long as that: the photos
/// themselves, and everything else, stay as private as they were.

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

  /// What the inbox is called in messages: "face inbox", "tag inbox".

  final String label;

  /// The Pod-relative path of the inbox.

  Future<String> path() async =>
      '${await PodMediaService.rootPath()}/$folderName';

  /// The URL of the inbox, with its trailing slash.

  Future<String> url() async {
    final url = await PodMediaService.folderUrl(await path());
    return url.endsWith('/') ? url : '$url/';
  }

  /// Whether the inbox is there, as it is only while photos are being looked
  /// at, or when that was cut short, as by the app being closed.

  Future<bool> exists() async => PodMediaService.folderExists(await url());

  /// Make the inbox, with the key every photo left in it is encrypted with,
  /// ready for [leave]. Nothing is shared yet.

  Future<void> prepare() async => setInheritKeyDir(await url());

  /// Ask the Analyser to look at the photos left in the inbox, by sharing
  /// the inbox with it. The share puts the inbox's key in the Analyser's
  /// Pod, and the server tells the Analyser at once. The photos go in first
  /// so that they are all there when it looks.

  Future<void> request() async {
    final url = await this.url();
    final webId = await getWebId();
    if (webId == null) throw StateError('Not logged in.');

    // grantPermission() declares the list as dynamic but reads each entry
    // as a String, so the mode names are what must be passed.

    try {
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
    } on Object {
      // The photos left for a request that was never made are of no use,
      // and an inbox left behind would be taken for one cut short.

      await _empty(url);
      rethrow;
    }
  }

  /// Stop sharing the inbox with the Analyser, and empty and remove it,
  /// along with any photo still waiting there. What has been found already
  /// stays where it was filed.

  Future<void> close() async {
    final url = await this.url();
    final webId = await getWebId();
    if (webId == null) throw StateError('Not logged in.');

    // A revocation that fails still ends with the inbox and its access list
    // removed below, which leaves the Analyser nothing to reach.

    try {
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
    } on Object catch (e) {
      debugPrint('PhotoPod: could not revoke the Analyser\'s access: $e');
    }
    await _empty(url);
  }

  // Remove everything in the inbox at [url], then the inbox itself.

  Future<void> _empty(String url) async {
    try {
      final listing = await getResourcesInContainer(url);
      for (final file in listing.files) {
        await _delete(file.startsWith('http') ? file : '$url$file');
      }
    } on Object catch (e) {
      debugPrint('PhotoPod: could not list the $label to empty it: $e');
    }
    await _delete('$url.acl');
    await _delete(url, ResourceContentType.directory);
  }

  /// Leave the photo at [photoPath] in the inbox as [picture], its large
  /// rendition, for the Analyser to look at. What the photo's EXIF block and
  /// the like say, such as where it was taken, is taken out first
  /// ([withoutMetadata]): the Analyser needs only the picture.

  Future<void> leave(String photoPath, Uint8List picture) async {
    final bare = withoutMetadata(picture);
    if (bare == null) throw StateError('not a JPEG or PNG picture');
    final inbox = await path();
    await writePod(
      '$inbox/${inboxKeyOf(photoPath)}$_photoSuffix',
      jsonEncode({
        'format': requestFormat,
        'version': 1,
        'image': base64Encode(bare),
      }),
      pathType: PathType.relativeToPod,
      createAcl: false,
      overwrite: true,
      inheritKeyFrom: '$inbox/',
    );
  }

  /// What the inbox holds.

  Future<InboxListing> list() async {
    final listing = await getResourcesInContainer(await url());
    final waiting = <String>{};
    final answered = <String>{};
    var done = false;
    for (final file in listing.files) {
      final name = file.substring(file.lastIndexOf('/') + 1);
      if (name == _doneName) {
        done = true;
      } else if (name.endsWith(resultSuffix)) {
        answered.add(name.substring(0, name.length - resultSuffix.length));
      } else if (name.endsWith(_photoSuffix)) {
        final key = name.substring(0, name.length - _photoSuffix.length);

        // An answer of another kind is never left here, but would not be a
        // photo either.

        if (!key.contains('.')) waiting.add(key);
      }
    }
    return (waiting: waiting, answered: answered, done: done);
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
    if (!await exists()) return;
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
