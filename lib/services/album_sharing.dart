/// Keeping the photos in a shared album shared with everyone the album is.
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

import 'package:flutter/foundation.dart';

import 'package:solidpod/solidpod.dart'
    show
        PathType,
        RecipientType,
        SolidFunctionCallStatus,
        agentStr,
        getAccessMode,
        getDataDirPath,
        getFileUrl,
        getRecipientType,
        getWebId,
        grantPermission,
        isUserLoggedIn,
        permStr,
        readPermission,
        readPod,
        revokePermission,
        turtleToTripleMap,
        writePod;

/// The file, in the PhotoPod data folder, that records what album sharing
/// has done. Like the album files it is JSON, and it is never shared.

const String albumSharesFileName = 'album-shares.json';

/// Someone an album is shared with, as the album file's access list names
/// them: an individual's WebID, a group's file, or the public or signed-in
/// users as a class.

@immutable
class ShareRecipient {
  /// The name the access list gives the recipient, which is what solidpod
  /// expects back when access is granted or revoked.

  final String key;

  /// What kind of recipient [key] names.

  final RecipientType type;

  /// The access modes granted, such as `Read` and `Write`.

  final Set<String> modes;

  const ShareRecipient({
    required this.key,
    required this.type,
    required this.modes,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'modes': modes.toList()..sort(),
  };

  static ShareRecipient? fromJson(String key, Object? json) {
    if (json is! Map) return null;
    final type = _typeNamed(json['type']);
    if (type == null) return null;
    return ShareRecipient(key: key, type: type, modes: _modes(json['modes']));
  }
}

/// Access PhotoPod has given one recipient to one photo or video because an
/// album holding it is shared with them.

@immutable
class AlbumGrant {
  /// What kind of recipient the grant was made to.

  final RecipientType type;

  /// The access modes the albums asked for.

  final Set<String> modes;

  /// The access modes the recipient already had to the file, from sharing it
  /// directly, before any album was shared with them. This is what they are
  /// left with once no shared album holds the file any more, so unsharing an
  /// album never takes away access that was given some other way.

  final Set<String> prior;

  const AlbumGrant({
    required this.type,
    required this.modes,
    this.prior = const {},
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'modes': modes.toList()..sort(),
    if (prior.isNotEmpty) 'prior': prior.toList()..sort(),
  };

  static AlbumGrant? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = _typeNamed(json['type']);
    if (type == null) return null;
    return AlbumGrant(
      type: type,
      modes: _modes(json['modes']),
      prior: _modes(json['prior']),
    );
  }
}

/// One change to make to one file's access for one recipient.

@immutable
class SharingChange {
  /// The Pod-relative path of the photo or video.

  final String path;

  /// Who the change is for.

  final String key;

  /// What kind of recipient [key] names.

  final RecipientType type;

  /// The access the shared albums now call for, or nothing when no shared
  /// album holding the file is shared with the recipient any more.

  final Set<String> modes;

  /// What album sharing has already given, if anything.

  final AlbumGrant? current;

  const SharingChange({
    required this.path,
    required this.key,
    required this.type,
    required this.modes,
    this.current,
  });

  /// Whether the change takes access away rather than giving it.

  bool get ends => modes.isEmpty;

  @override
  String toString() =>
      '${ends ? 'end' : 'grant ${modes.join('+')}'} $key on $path';
}

/// Work out what has to change for every photo and video to be shared with
/// exactly the people their albums are shared with.
///
/// [albums] maps each album's name to the paths of what it holds,
/// [recipients] maps each album's name to who it is shared with, and
/// [grants] is what album sharing has given so far, by path and recipient.
///
/// A photo in several albums is shared with everyone any of them is shared
/// with, and each recipient gets every access mode any of those albums gives
/// them. So unsharing one album takes a photo away from a recipient only
/// when no other album holding it is still shared with them. Paths that are
/// URLs belong to someone else's Pod — photos shared with the user and then
/// put into one of the user's albums — and are left out, since only their
/// owner can share them.

List<SharingChange> planSharing({
  required Map<String, Set<String>> albums,
  required Map<String, Map<String, ShareRecipient>> recipients,
  required Map<String, Map<String, AlbumGrant>> grants,
}) {
  final wanted = <String, Map<String, ShareRecipient>>{};

  for (final album in albums.entries) {
    final sharedWith = recipients[album.key];
    if (sharedWith == null || sharedWith.isEmpty) continue;
    for (final path in album.value) {
      if (path.contains('://')) continue;
      final forPath = wanted.putIfAbsent(path, () => {});
      for (final recipient in sharedWith.values) {
        if (recipient.modes.isEmpty) continue;
        final before = forPath[recipient.key];
        forPath[recipient.key] = ShareRecipient(
          key: recipient.key,
          type: recipient.type,
          modes: {...?before?.modes, ...recipient.modes},
        );
      }
    }
  }

  final changes = <SharingChange>[];

  for (final entry in wanted.entries) {
    for (final recipient in entry.value.values) {
      final current = grants[entry.key]?[recipient.key];
      if (current != null &&
          current.type == recipient.type &&
          setEquals(current.modes, recipient.modes)) {
        continue;
      }
      changes.add(
        SharingChange(
          path: entry.key,
          key: recipient.key,
          type: recipient.type,
          modes: recipient.modes,
          current: current,
        ),
      );
    }
  }

  for (final entry in grants.entries) {
    for (final grant in entry.value.entries) {
      if (wanted[entry.key]?.containsKey(grant.key) ?? false) continue;
      changes.add(
        SharingChange(
          path: entry.key,
          key: grant.key,
          type: grant.value.type,
          modes: const {},
          current: grant.value,
        ),
      );
    }
  }

  return changes;
}

/// Sharing albums, and keeping what is in them shared to match.
///
/// Sharing an album is Solid sharing of the album file: the share dialogue
/// writes the album file's access list, and that list is the one record of
/// who the album is shared with. The photos and videos in the album then
/// follow it. Whenever an album is shared or unshared, or something is put
/// into or taken out of a shared album, [planSharing] works out which files
/// have to change for whom, and [apply] makes those changes.
///
/// What album sharing has given is kept in [albumSharesFileName], so that it
/// can later be taken back without touching access given some other way —
/// such as a photo the user shared with someone directly.

class AlbumSharing extends ChangeNotifier {
  final Map<String, Map<String, ShareRecipient>> _recipients = {};
  final Map<String, Map<String, AlbumGrant>> _grants = {};

  Future<void>? _loading;
  bool _loaded = false;

  /// Whether the album called [album] is shared with anyone, as far as
  /// PhotoPod last saw.

  bool isShared(String album) => _recipients[album]?.isNotEmpty ?? false;

  /// Who the album called [album] is shared with.

  Map<String, ShareRecipient> recipientsOf(String album) =>
      Map.unmodifiable(_recipients[album] ?? const {});

  /// Read the record of album sharing from the Pod, once.

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      if (!await isUserLoggedIn()) return;
      final String content;
      try {
        content = await readPod(
          await _ledgerPath(),
          pathType: PathType.relativeToPod,
        );
      } on Object {
        // No album has been shared yet, so there is nothing to read.

        _loaded = true;
        return;
      }
      _decode(content);
      _loaded = true;
    } on Object catch (e) {
      debugPrint('PhotoPod: could not read the album sharing record: $e');
    } finally {
      notifyListeners();
    }
  }

  /// Read afresh who the album called [album], whose file is at [url], is
  /// shared with. The share dialogue may just have changed it.

  Future<void> refresh(String album, String url) async {
    await load();
    final me = await getWebId();
    final found = <String, ShareRecipient>{};

    try {
      final permissions = await readPermission(fileName: url, isFile: true);
      for (final entry in permissions.entries) {
        final key = '${entry.key}';
        if (key == me || key == 'card#me') continue;
        final detail = entry.value;
        if (detail is! Map) continue;
        final modes = _modes(detail[permStr]);
        if (modes.isEmpty) continue;
        found[key] = ShareRecipient(
          key: key,
          type: getRecipientType('${detail[agentStr]}', key),
          modes: modes,
        );
      }
    } on Object catch (e) {
      // An album file that has never been shared has no access list of its
      // own, which is simply an album shared with nobody.

      debugPrint('PhotoPod: no access list for $url: $e');
    }

    if (found.isEmpty) {
      if (_recipients.remove(album) == null) return;
    } else {
      _recipients[album] = found;
    }
    await _save();
    notifyListeners();
  }

  /// The changes needed for every file to be shared as [albums] — each
  /// album's name mapped to the paths of what it holds — call for.

  Future<List<SharingChange>> plan(Map<String, Set<String>> albums) async {
    await load();
    return planSharing(
      albums: albums,
      recipients: _recipients,
      grants: _grants,
    );
  }

  /// Make [changes] on the Pod, returning what went wrong, file by file.
  ///
  /// Each change is recorded as it succeeds, so a failure part way through
  /// leaves the record true to the Pod and the next plan tries only what is
  /// still outstanding. The caller must have secured the security key, since
  /// sharing an encrypted file shares its key.

  Future<List<String>> apply(List<SharingChange> changes) async {
    if (changes.isEmpty) return const [];
    final me = await getWebId();
    if (me == null) return const ['You need to be logged in to share.'];

    final failed = <String>[];
    for (final change in changes) {
      try {
        final url = await getFileUrl(change.path);
        if (change.ends) {
          await _end(change, url, me);
          _grants[change.path]?.remove(change.key);
          if (_grants[change.path]?.isEmpty ?? false) {
            _grants.remove(change.path);
          }
        } else {
          final prior =
              change.current?.prior ?? await _modesInAcl(url, change.key);
          final target = {...prior, ...change.modes};
          if (change.current != null || !prior.containsAll(change.modes)) {
            await _grant(url, change.key, change.type, target, me);
          }
          _grants.putIfAbsent(change.path, () => {})[change.key] = AlbumGrant(
            type: change.type,
            modes: change.modes,
            prior: prior,
          );
        }
      } on Object catch (e) {
        failed.add('${_nameOf(change.path)}: $e');
      }
    }

    await _save();
    notifyListeners();
    return failed;
  }

  /// Share the album called [album], whose file is at [url], with
  /// [recipients], for an album that has just been renamed: the new file
  /// starts with no access list, so everyone the old one was shared with is
  /// given the same access to it. What the album holds is unchanged, so its
  /// photos need nothing doing to them.

  Future<List<String>> shareAlbumFile(
    String album,
    String url,
    Map<String, ShareRecipient> recipients,
  ) async {
    await load();
    if (recipients.isEmpty) return const [];
    final me = await getWebId();
    if (me == null) return const ['You need to be logged in to share.'];

    final failed = <String>[];
    final shared = <String, ShareRecipient>{};
    for (final recipient in recipients.values) {
      try {
        await _grant(url, recipient.key, recipient.type, recipient.modes, me);
        shared[recipient.key] = recipient;
      } on Object catch (e) {
        failed.add('${_label(recipient)}: $e');
      }
    }
    if (shared.isNotEmpty) _recipients[album] = shared;
    await _save();
    notifyListeners();
    return failed;
  }

  /// Stop sharing the album called [album], whose file is at [url], with
  /// anyone, ahead of the album being deleted or renamed, so that its
  /// recipients are told it has gone. Its photos are dealt with by the next
  /// plan, once the album has gone.

  Future<List<String>> unshareAlbum(String album, String url) async {
    await load();
    final recipients = _recipients.remove(album);
    if (recipients == null || recipients.isEmpty) return const [];
    final me = await getWebId();
    if (me == null) return const ['You need to be logged in to share.'];

    final failed = <String>[];
    for (final recipient in recipients.values) {
      try {
        await _revoke(url, recipient.key, recipient.type, recipient.modes, me);
      } on Object catch (e) {
        failed.add('${_label(recipient)}: $e');
      }
    }
    await _save();
    notifyListeners();
    return failed;
  }

  /// Forget what album sharing gave to [paths] and anything beneath them,
  /// for files that have just been deleted or moved. Deleting a file already
  /// takes away everyone's access to it, and a moved file is a new file that
  /// the next plan shares afresh.

  Future<void> forget(Iterable<String> paths) async {
    await load();
    final gone = paths.toList();
    final before = _grants.length;
    _grants.removeWhere(
      (path, _) =>
          gone.any((each) => path == each || path.startsWith('$each/')),
    );
    if (_grants.length == before) return;
    await _save();
  }

  // Take away what album sharing gave, leaving the recipient with whatever
  // they had before it.

  Future<void> _end(SharingChange change, String url, String me) async {
    final current = change.current;
    if (current == null) return;
    if (current.prior.containsAll(current.modes)) return;
    if (current.prior.isNotEmpty) {
      await _grant(url, change.key, change.type, current.prior, me);
    } else {
      await _revoke(url, change.key, change.type, current.modes, me);
    }
  }

  static Future<void> _grant(
    String url,
    String key,
    RecipientType type,
    Set<String> modes,
    String me,
  ) async {
    final isGroup = type == RecipientType.group;
    final status = await grantPermission(
      fileName: url,
      permissionList: modes.toList(),
      recipientType: type,
      recipientWebIdList: isGroup ? await _groupMembers(key) : [key],
      ownerWebId: me,
      granterWebId: me,
      groupName: isGroup ? _groupName(key) : null,
    );
    if (status != SolidFunctionCallStatus.success) {
      throw Exception(
        status == SolidFunctionCallStatus.notInitialised
            ? 'the recipient has not set up their Pod yet'
            : 'the Pod did not accept the change ($status)',
      );
    }
  }

  static Future<void> _revoke(
    String url,
    String key,
    RecipientType type,
    Set<String> modes,
    String me,
  ) async {
    final status = await revokePermission(
      fileName: url,
      permissionList: modes.toList(),
      recipientIndOrGroupWebId: key,
      ownerWebId: me,
      granterWebId: me,
      recipientType: type,
    );
    if (status != SolidFunctionCallStatus.success) {
      throw Exception('the Pod did not accept the change ($status)');
    }
  }

  // The access [key] already has to the file at [url], which is nothing
  // when the file has no access list of its own yet.

  static Future<Set<String>> _modesInAcl(String url, String key) async {
    try {
      final permissions = await readPermission(fileName: url, isFile: true);
      final detail = permissions[key];
      return detail is Map ? _modes(detail[permStr]) : <String>{};
    } on Object {
      return <String>{};
    }
  }

  // A group's members are listed in the group's own file in the data folder,
  // which is where solidpod put it when the group was first shared with.

  static Future<List<String>> _groupMembers(String key) async {
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

  static String _groupName(String key) {
    final file = key.substring(key.lastIndexOf('/') + 1);
    return file.endsWith('.ttl') ? file.substring(0, file.length - 4) : file;
  }

  static String _label(ShareRecipient recipient) => switch (recipient.type) {
    RecipientType.public => 'Everyone',
    RecipientType.authUser => 'Signed-in users',
    RecipientType.group => 'Group ${_groupName(recipient.key)}',
    _ => recipient.key,
  };

  static String _nameOf(String path) =>
      path.substring(path.lastIndexOf('/') + 1);

  void _decode(String content) {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;

    final albums = decoded['albums'];
    if (albums is Map) {
      for (final album in albums.entries) {
        final found = <String, ShareRecipient>{};
        final value = album.value;
        if (value is! Map) continue;
        for (final entry in value.entries) {
          final recipient = ShareRecipient.fromJson(
            '${entry.key}',
            entry.value,
          );
          if (recipient != null) found[recipient.key] = recipient;
        }
        if (found.isNotEmpty) _recipients['${album.key}'] = found;
      }
    }

    final grants = decoded['grants'];
    if (grants is Map) {
      for (final item in grants.entries) {
        final found = <String, AlbumGrant>{};
        final value = item.value;
        if (value is! Map) continue;
        for (final entry in value.entries) {
          final grant = AlbumGrant.fromJson(entry.value);
          if (grant != null) found['${entry.key}'] = grant;
        }
        if (found.isNotEmpty) _grants['${item.key}'] = found;
      }
    }
  }

  // The record is written only when it has changed, and never encrypted, for
  // the same reason as the album files: reading it must not need the key.

  Future<void> _save() async {
    try {
      await writePod(
        await _ledgerPath(),
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'albums': {
            for (final album in _recipients.entries)
              album.key: {
                for (final recipient in album.value.values)
                  recipient.key: recipient.toJson(),
              },
          },
          'grants': {
            for (final item in _grants.entries)
              item.key: {
                for (final grant in item.value.entries)
                  grant.key: grant.value.toJson(),
              },
          },
        }),
        encrypted: false,
        overwrite: true,
        pathType: PathType.relativeToPod,
      );
    } on Object catch (e) {
      debugPrint('PhotoPod: could not save the album sharing record: $e');
    }
  }

  static Future<String> _ledgerPath() async =>
      '${await getDataDirPath()}/$albumSharesFileName';
}

RecipientType? _typeNamed(Object? name) {
  for (final type in RecipientType.values) {
    if (type.name == name) return type;
  }
  return null;
}

// Access modes arrive spelt in several ways — `Read`, `read`, or the tail of
// an ACL URI — and are kept in the one spelling solidpod writes.

Set<String> _modes(Object? value) {
  if (value is! Iterable) return <String>{};
  final modes = <String>{};
  for (final each in value) {
    try {
      modes.add(getAccessMode('$each'.split('#').last).mode);
    } on Object {
      // A mode PhotoPod does not know is left alone rather than guessed at.
    }
  }
  return modes;
}
