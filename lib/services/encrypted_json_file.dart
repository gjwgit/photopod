/// PhotoPod's own bookkeeping files, kept encrypted on the Pod.
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

import 'package:flutter/foundation.dart';

import 'package:solidpod/solidpod.dart'
    show
        KeyManager,
        PathType,
        ResourceContentType,
        deleteFile,
        deleteResource,
        getDataDirPath,
        getFileUrl,
        readPod,
        writePod;

import 'package:photopod/constants/media.dart';
import 'package:photopod/services/pod_keys.dart';
import 'package:photopod/services/pod_media_service.dart';

/// A JSON file of PhotoPod's own, such as the favourites, held encrypted in
/// the PhotoPod data folder.
///
/// solidpod only encrypts a resource whose name ends in `.ttl`, so the file
/// called [fileName] is stored as `<fileName>.enc.ttl`: the JSON is the
/// content solidpod encrypts and wraps in Turtle. It has an individual key of
/// its own, which is added to the key file once, when the file is first
/// written, and reused on every later write.
///
/// Earlier builds wrote the file as plain JSON under [fileName] itself. That
/// copy is still read while there is no encrypted one, and is removed the
/// first time the file is written, so the move to encryption needs nothing
/// from the user.

class EncryptedJsonFile {
  /// The name the file had as plain JSON, such as `favourites.json`, or its
  /// path within the data folder, such as `albums/Holiday.json`.

  final String fileName;

  /// Whether the file is given an access list of its own. Only a file that
  /// may be shared needs one.

  final bool createAcl;

  const EncryptedJsonFile(this.fileName, {this.createAcl = false});

  /// The name the file is stored under.

  String get storedName => '$fileName$encryptedSuffix';

  /// The Pod-relative path of the encrypted file.

  Future<String> path() async => '${await getDataDirPath()}/$storedName';

  /// The URL of the encrypted file.

  Future<String> url() async => getFileUrl(await path());

  /// Whether the encrypted file exists, and so whether reading it needs the
  /// security key.

  Future<bool> exists() async => PodMediaService.fileExists(await url());

  /// The JSON the file holds, or null when there is none yet.
  ///
  /// Reading the encrypted file needs the security key, and throws
  /// [SecurityKeyNeeded] when it has not been entered. The caller can try
  /// again once [PodKeys.unlocked] completes.

  Future<String?> read() async {
    if (await exists()) {
      await PodKeys.prime();
      if (!PodKeys.isPrimed) throw SecurityKeyNeeded(fileName);
      return readPod(await path(), pathType: PathType.relativeToPod);
    }

    final legacy = await _legacyPath();
    if (!await PodMediaService.fileExists(await getFileUrl(legacy))) {
      return null;
    }
    final json = await readPod(legacy, pathType: PathType.relativeToPod);

    // Encrypted at once when the key is to hand — as it is whenever this
    // device remembers it — rather than waiting for the next change, so the
    // plain copy does not linger.

    await PodKeys.prime();
    if (PodKeys.isPrimed) {
      try {
        await write(json);
      } on Object catch (e) {
        debugPrint('PhotoPod: could not encrypt $fileName: $e');
      }
    }
    return json;
  }

  /// Store [json], encrypted, and remove any plain copy an earlier build
  /// left behind.
  ///
  /// Throws [SecurityKeyNeeded] when the security key has not been entered:
  /// unlike a read, a write cannot simply wait, since the caller is waiting
  /// to tell the user whether it worked.

  Future<void> write(String json) async {
    if (!await KeyManager.hasSecurityKey()) throw SecurityKeyNeeded(fileName);
    await PodKeys.prime();
    await writePod(
      await path(),
      json,
      overwrite: true,
      createAcl: createAcl,
      pathType: PathType.relativeToPod,
    );
    await _dropLegacy();
  }

  /// Remove the file, encrypted copy and plain alike, along with the key and
  /// the access list of the encrypted one. A file already gone counts as
  /// removed.

  Future<void> delete() async {
    final url = await this.url();
    if (await PodMediaService.fileExists(url)) {
      await PodKeys.prime();
      await deleteFile(fileUrl: url);
    }
    final legacy = await getFileUrl(await _legacyPath());
    if (await PodMediaService.fileExists(legacy)) {
      await deleteResource(legacy, ResourceContentType.any);
    }
  }

  // The plain copy is looked for once per session, and only after an
  // encrypted copy has been written to take its place.

  static final Set<String> _checkedLegacy = <String>{};

  Future<void> _dropLegacy() async {
    final url = await getFileUrl(await _legacyPath());
    if (!_checkedLegacy.add(url)) return;
    try {
      if (await PodMediaService.fileExists(url)) {
        await deleteResource(url, ResourceContentType.any);
      }
    } on Object catch (e) {
      debugPrint('PhotoPod: could not remove the plain $fileName: $e');
    }
  }

  Future<String> _legacyPath() async => '${await getDataDirPath()}/$fileName';
}

/// Raised when one of PhotoPod's encrypted files is needed before the user
/// has entered their security key.

class SecurityKeyNeeded extends PodMediaException {
  SecurityKeyNeeded(String fileName)
    : super('Your security key is needed to open $fileName.');
}
