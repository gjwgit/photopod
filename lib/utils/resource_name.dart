/// The names PhotoPod is allowed to give a resource on the Pod.
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

/// Why PhotoPod will not put a space, or anything else that has to be
/// percent-escaped, into a resource name.
///
/// solidpod files the encryption key for a resource under a URL it rebuilds
/// from the resource's own URL, and the two halves of that round trip do not
/// agree about escaping: the path is taken out of the URL with
/// `Uri.pathSegments`, which *decodes* each segment, and the URL is then put
/// back together by joining the segments verbatim, which does *not* re-encode
/// them. A photo stored as `my%20photo.jpg.enc.ttl` therefore has its key
/// filed under `.../my photo.jpg.enc.ttl`, where nothing will ever look for
/// it, and the key file itself ends up holding a subject IRI with a raw space
/// in it — which is not valid Turtle, and which costs every key written after
/// it when the file is next read back.
///
/// Keeping every name inside the set of characters that percent-encoding
/// leaves alone makes that round trip the identity, and so makes the whole
/// question go away.
///
/// The set is the one `Uri.encodeComponent` passes through unchanged —
/// letters, digits, and `- _ . ! ~ * ' ( )` — less the asterisk, which no
/// Windows file system will accept and which a photo downloaded out of the
/// Pod would trip over.

final RegExp _unsafeCharacters = RegExp(r"[^A-Za-z0-9\-_.!~'()]");

/// Whether [name] can be used as a resource name exactly as it stands.

bool isSafeResourceName(String name) =>
    name.isNotEmpty && !_unsafeCharacters.hasMatch(name);

/// [name] with every character that would have to be escaped replaced by an
/// underscore, so that the name survives a trip through a URL unchanged.
///
/// A run of such characters becomes a single underscore rather than one each,
/// so `holiday #1 (50%).jpg` reads as `holiday_1_(50_).jpg` rather than as a
/// row of underscores. The full stops that separate the extension are in the
/// safe set, so the extension always survives and the file stays recognisable
/// as a photo or a video.

String safeResourceName(String name) {
  final replaced = name
      .replaceAll(_unsafeCharacters, '_')
      .replaceAll(RegExp('_+'), '_');

  // Leading and trailing underscores carry no information.

  final trimmed = replaced.replaceAll(RegExp(r'^_+|_+$'), '');

  // A name written entirely in a non-Latin script is left with nothing in
  // front of its extension, and a resource whose name begins with a full stop
  // is hidden. Such a name is given a stem, while a name that began with a
  // full stop of its own accord is left alone.

  if (trimmed.isEmpty) return 'file';
  return trimmed.startsWith('.') && !name.startsWith('.')
      ? 'file$trimmed'
      : trimmed;
}

/// The single character in [name] that keeps it from being used as it stands,
/// or null when there is none.

String? firstUnsafeCharacter(String name) =>
    _unsafeCharacters.firstMatch(name)?.group(0);

/// The first part of [podPath] that PhotoPod could not write into, or null
/// when the whole path is usable.
///
/// A folder created by an earlier build of PhotoPod may carry a
/// percent-escaped name, and anything written inside it would lose its
/// encryption key. Finding out before the write beats failing part way
/// through it.

String? unsafeSegmentOf(String podPath) {
  for (final segment in podPath.split('/')) {
    if (segment.isNotEmpty && !isSafeResourceName(segment)) return segment;
  }
  return null;
}
