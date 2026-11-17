/// Recognise a photo or video that is already in the Pod.
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

import 'package:crypto/crypto.dart';
import 'package:solidpod/solidpod.dart' show getFileUrl;

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/media_catalog.dart';
import 'package:photopod/services/pod_media_service.dart';

/// The SHA-256 digest of [bytes], as the lower-case hexadecimal that
/// [CatalogEntry.hash] holds.

String contentHashOf(Uint8List bytes) => sha256.convert(bytes).toString();

/// Files larger than this are digested on a background isolate, so that a
/// long video does not hold up the progress spinner.

const int _hashInBackgroundFrom = 1 << 20;

/// [contentHashOf] [bytes], away from the user interface for a large file.

Future<String> hashContent(Uint8List bytes) =>
    bytes.length < _hashInBackgroundFrom
    ? Future.value(contentHashOf(bytes))
    : compute(contentHashOf, bytes);

/// The most catalogued items without a digest that are fetched and digested
/// for any one file being added. Each means downloading a whole original,
/// so a name shared by many photos, such as `IMG_0001.JPG`, must not turn
/// one upload into hundreds of downloads.

const int maxDuplicateChecks = 12;

/// How far apart two dates may be and still be taken as the same moment.
/// Cameras record whole seconds, and the dates are stored to the second.

const Duration _sameMoment = Duration(seconds: 1);

/// The catalogued items among [entries] that may be the same file as one
/// called [name], taken at [taken], whose digest is [hash].
///
/// The [known] matches already have that digest recorded, and are certainly
/// the same file. The [possible] ones have no digest recorded yet, so cannot
/// be ruled out without fetching them, but are the same kind of media and
/// share either the name or the moment the photo was taken, which a copy of
/// the same file almost always does. Those sharing the moment are listed
/// first, being the likelier, and no more than [limit] are listed.

({List<CatalogEntry> known, List<CatalogEntry> possible}) duplicateCandidates(
  Iterable<CatalogEntry> entries, {
  required String hash,
  required String name,
  DateTime? taken,
  int limit = maxDuplicateChecks,
}) {
  final kind = kindOf(name);
  final lowerName = name.toLowerCase();
  final known = <CatalogEntry>[];
  final sameMoment = <CatalogEntry>[];
  final sameName = <CatalogEntry>[];

  for (final entry in entries) {
    if (entry.hash == hash) {
      known.add(entry);
      continue;
    }
    if (entry.hash != null || kind == null) continue;
    final entryName = entry.name ?? displayNameOf(_storedNameOf(entry.path));
    if (kindOf(entryName) != kind) continue;
    final when = entry.taken == null ? null : DateTime.tryParse(entry.taken!);
    if (taken != null &&
        when != null &&
        when.difference(taken).abs() < _sameMoment) {
      sameMoment.add(entry);
    } else if (entryName.toLowerCase() == lowerName) {
      sameName.add(entry);
    }
  }

  return (
    known: known,
    possible: [...sameMoment, ...sameName].take(limit).toList(),
  );
}

String _storedNameOf(String path) =>
    PodMediaService.decodeName(path.substring(path.lastIndexOf('/') + 1));

/// Finding the photo or video in the user's Pod that a file being added is
/// an exact copy of.
///
/// Two files are taken as duplicates only when every byte is the same, which
/// is judged by the SHA-256 digest of each. The digest of every file added
/// is recorded in [MediaCatalog], so a later copy is found at once. A file
/// added before digests were kept has none, so the likely matches among
/// those (see [duplicateCandidates]) are fetched and digested in turn, and
/// what is learnt recorded so that none is fetched for this again.

class MediaDuplicates {
  const MediaDuplicates._();

  /// The catalog entry of the file already in the Pod that is the same as
  /// the one called [name], taken at [taken], whose digest is [hash], or
  /// null when there is none.
  ///
  /// A file that cannot be fetched is passed over rather than failing the
  /// upload: at worst a duplicate goes unnoticed, as it would have before.

  static Future<CatalogEntry?> find({
    required String hash,
    required String name,
    DateTime? taken,
  }) async {
    await MediaCatalog.ensureLoaded();
    final (:known, :possible) = duplicateCandidates(
      MediaCatalog.entries,
      hash: hash,
      name: name,
      taken: taken,
    );

    // An entry can outlive its file when a delete could not tidy the
    // catalog, so a match is only reported once its file is seen to be
    // there.

    for (final entry in known) {
      if (await _exists(entry.path)) return entry;
    }

    final learnt = <String, String>{};
    CatalogEntry? found;
    for (final entry in possible) {
      try {
        final bytes = await PodMediaService.readBytes(await itemFor(entry));
        final digest = await hashContent(bytes);
        learnt[entry.path] = digest;
        if (digest == hash) {
          found = entry;
          break;
        }
      } on Object catch (e) {
        debugPrint('PhotoPod: could not compare ${entry.path} with $name: $e');
      }
    }

    if (learnt.isNotEmpty) {
      try {
        await MediaCatalog.setHashes(learnt);
      } on Object catch (e) {
        debugPrint('PhotoPod: could not record what was learnt: $e');
      }
    }
    return found == null ? null : MediaCatalog.entryOf(found.path) ?? found;
  }

  /// The item [entry] catalogues, as it would be listed, so that it can be
  /// fetched, pictured or looked up among the favourites and albums.

  static Future<MediaItem> itemFor(CatalogEntry entry) async {
    final path = entry.path;
    final stored = _storedNameOf(path);
    return MediaItem(
      name: entry.name ?? displayNameOf(stored),
      rawName: path.substring(path.lastIndexOf('/') + 1),
      path: path,
      url: await getFileUrl(path),
      isFolder: false,
      isEncrypted: stored.endsWith(encryptedSuffix),
      taken: entry.taken == null ? null : DateTime.tryParse(entry.taken!),
    );
  }

  static Future<bool> _exists(String path) async {
    try {
      return await PodMediaService.fileExists(await getFileUrl(path));
    } on Object catch (e) {
      debugPrint('PhotoPod: could not tell whether $path is there: $e');
      return false;
    }
  }
}
