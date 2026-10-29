/// Carrying access from one file to another, and reading group members.
///
/// Copyright (C) 2026, Togaware Pty Ltd.
///
/// Licensed under the GNU General Public License, Version 3 (the "License").
///
/// License: https://opensource.org/license/gpl-3-0
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free
// Software
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

part of 'album_sharing.dart';

/// Give the file at [toUrl] the same access as the file at [fromUrl] has,
/// for a file that has been copied to a new name and is about to be
/// removed, returning what could not be given.
///
/// Everyone the original was shared with, whether directly or through an
/// album, is granted the same on the copy, which also shares its key and
/// tells them of it. Removing the original then tells them it has gone.

Future<List<String>> carryAccess(String fromUrl, String toUrl) async {
  final me = await getWebId();
  if (me == null) return const [];

  final Map<dynamic, dynamic> permissions;
  try {
    permissions = await readPermission(fileName: fromUrl, isFile: true);
  } on Object {
    // No access list of its own: shared with nobody.

    return const [];
  }

  final failed = <String>[];
  for (final entry in permissions.entries) {
    final key = '${entry.key}';
    if (key == me || key == 'card#me') continue;
    final detail = entry.value;
    if (detail is! Map) continue;
    final modes = _modes(detail[permStr]);
    if (modes.isEmpty) continue;
    final recipient = ShareRecipient(
      key: key,
      type: getRecipientType('${detail[agentStr]}', key),
      modes: modes,
    );
    try {
      await AlbumSharing._grant(toUrl, key, recipient.type, modes, me);
    } on Object catch (e) {
      failed.add('${AlbumSharing._label(recipient)}: $e');
    }
  }
  return failed;
}

// A group's members are listed in the group's own file in the data folder,
// which is where solidpod put it when the group was first shared with.

Future<List<String>> _groupMembersOf(String key) async {
  final path = key.contains('://') ? key : '${await getDataDirPath()}/$key';
  final content = await readPod(
    path,
    pathType: key.contains('://')
        ? PathType.absoluteUrl
        : PathType.relativeToPod,
  );
  final members = <String>{};
  for (final predicates in turtleToTripleMap(content).values) {
    for (final entry in predicates.entries) {
      if (!entry.key.endsWith('hasMember')) continue;
      final value = entry.value;
      if (value is Iterable) {
        members.addAll(value.map((each) => '$each'));
      } else if (value != null) {
        members.add('$value');
      }
    }
  }
  return members.toList();
}

// The access [key] already has to the file at [url], which is nothing
// when the file has no access list of its own yet.

Future<Set<String>> _modesInAclOf(String url, String key) async {
  try {
    final permissions = await readPermission(fileName: url, isFile: true);
    final detail = permissions[key];
    return detail is Map ? _modes(detail[permStr]) : <String>{};
  } on Object {
    return <String>{};
  }
}

// A file being shared for the first time through an album is given its
// name inside it, if it was written before names were kept there, so that
// its recipients see the name. Paths already named are remembered, since a
// file is often shared with several people at once.

final Set<String> _namedInside = {};

Future<void> _ensureNamedInside(String path) async {
  final stored = path.substring(path.lastIndexOf('/') + 1);
  if (!isRandomStoredName(stored) || !_namedInside.add(path)) return;
  try {
    await PodMediaOps.ensureNameInside(path);
  } on Object catch (e) {
    debugPrint('PhotoPod: could not name $path inside: $e');
  }
}
