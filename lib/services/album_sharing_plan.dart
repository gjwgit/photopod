/// Who an album is shared with, and what that means for its photos.
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

part of 'album_sharing.dart';

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
