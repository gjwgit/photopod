/// Declining what someone else has shared with the user.
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

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:solidpod/solidpod.dart'
    show
        getDataDirPath,
        getFileUrl,
        getResource,
        turtleToTripleMap,
        updateFileByQuery;

import 'package:photopod/services/shared_log.dart';

// The vocabularies solidpod writes the shared keys and the permission log in.

const String _resourceIds = 'https://solidcommunity.au/predicates/resourceid#';
const String _data = 'https://solidcommunity.au/predicates/data#';

/// The URL of the permission log in the user's own Pod, which sits beside the
/// data folder in the app's own logs folder.

Future<String> permissionLogUrl() async =>
    getFileUrl('${await _appDir()}/logs/permissions-log.ttl');

Future<String> _appDir() async => (await getDataDirPath()).split('/').first;

/// Decline the resource at [url], owned by [owner], shared with the user [me]
/// as the latest permission log [line] for it records, if there is one.
///
/// Only the owner can take the user out of the resource's ACL, so this is
/// done entirely in the user's own Pod: the key the owner shared to decrypt
/// it is removed from the user's shared keys, and a revocation is added to
/// the user's permission log, which from then on is the latest line for it.

Future<void> declineShare({
  required String url,
  required String owner,
  required String me,
  PermissionLogLine? line,
}) async {
  // The key is filed under the WebID as the owner typed it, which the log
  // line records, and may differ from the login's own spelling.

  await _removeSharedKey(url, {?line?.recipient, me});

  await updateFileByQuery(
    await permissionLogUrl(),
    declineLogQuery(
      url: url,
      owner: owner,
      me: me,
      recipient: line?.recipient ?? me,
      permissions: line?.permissions ?? 'read',
      after: line?.time,
    ),
  );
}

// Remove from the user's shared keys the key filed for [url] under any of
// the [recipients] spellings, just as solidpod does when the owner revokes
// access: the entry is named by the SHA-256 of the URL and the recipient's
// WebID, and is deleted along with exactly the values it holds.

Future<void> _removeSharedKey(String url, Set<String> recipients) async {
  final keysUrl = await getFileUrl('${await _appDir()}/shared/shared-keys.ttl');
  final Map<String, Map<String, dynamic>> keys;
  try {
    keys = turtleToTripleMap(utf8.decode(await getResource(keysUrl)));
  } on Object {
    return; // No shared keys at all, so none to remove.
  }

  for (final recipient in recipients) {
    final id = sha256.convert(utf8.encode(url + recipient)).toString();
    final entry = keys['$_resourceIds$id'];
    if (entry == null) continue;

    final facts = [
      for (final MapEntry(:key, :value) in entry.entries)
        if (key.startsWith(_data))
          for (final each in value is List ? value : [value])
            '<$key> "${_escape('$each')}"',
    ];
    if (facts.isEmpty) continue;
    await updateFileByQuery(
      keysUrl,
      'DELETE DATA { <$_resourceIds$id> ${facts.join(' ; ')} . }',
    );
  }
}

String _escape(String literal) =>
    literal.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

/// The SPARQL update that adds to the user's permission log the line
/// recording that [me] has declined the photo at [url], owned by [owner],
/// shared with [me] as [recipient] with [permissions].
///
/// The line is written just as solidpod writes a revocation, local time and
/// all. Its time is now,
/// or, should this device's clock be behind the one the grant was written
/// with, a second after the grant's time [after], so that it is always the
/// latest line for the photo.

String declineLogQuery({
  required String url,
  required String owner,
  required String me,
  required String recipient,
  required String permissions,
  String? after,
  DateTime? now,
}) {
  var at = now ?? DateTime.now();
  final grantedAt = after == null ? null : _parseLogTime(after);
  if (grantedAt != null && !at.isAfter(grantedAt)) {
    at = grantedAt.add(const Duration(seconds: 1));
  }
  final time = _logTime(at);
  final id = '$time${at.millisecond.toString().padLeft(3, '0')}';
  final record = '$time;$url;$owner;revoke;$me;$recipient;$permissions';
  return 'PREFIX logId: <https://solidcommunity.au/predicates/logid#> '
      'PREFIX data: <https://solidcommunity.au/predicates/data#> '
      'INSERT DATA {logId:$id data:log "<$record>"};';
}

String _two(int n) => n.toString().padLeft(2, '0');

String _logTime(DateTime at) =>
    '${at.year.toString().padLeft(4, '0')}${_two(at.month)}${_two(at.day)}'
    'T${_two(at.hour)}${_two(at.minute)}${_two(at.second)}';

DateTime? _parseLogTime(String time) {
  final match = RegExp(
    r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})',
  ).firstMatch(time);
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
}
