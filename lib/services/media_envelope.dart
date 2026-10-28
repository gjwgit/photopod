/// What a photo or video file holds: its bytes, and the name the user knows
/// it by.
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
import 'dart:typed_data';

/// The contents of one media file once it has been decrypted.

typedef MediaContent = ({Uint8List bytes, String? name});

/// Raised when what a media file holds is in neither of the formats PhotoPod
/// writes.

class MediaEnvelopeException extends FormatException {
  const MediaEnvelopeException(super.message);
}

/// The marker that tells PhotoPod's own header apart from anything else.

const String _marker = 'photopod-media';

/// The version of the header written now.

const int envelopeVersion = 1;

/// The text solidpod encrypts and wraps in Turtle for a file called [name]
/// holding [bytes].
///
/// The first line is a small JSON object carrying the name and the second is
/// the bytes in base64:
///
/// ```text
/// {"format":"photopod-media","version":1,"name":"海滩 #1 (50%).jpg"}
/// iVBORw0KGgo...
/// ```
///
/// The name therefore lives inside the file it names, encrypted under the
/// same key as the photo. The server sees only the random name the file is
/// stored under, while anyone the file is shared with decrypts the name along
/// with the picture and so sees it exactly as the owner does. JSON escapes
/// whatever the name holds, in any script and with any punctuation, and
/// base64 never contains a line break or a brace, so the two parts cannot be
/// confused.

String encodeMedia(String name, Uint8List bytes) {
  final header = jsonEncode({
    'format': _marker,
    'version': envelopeVersion,
    'name': name,
  });
  return '$header\n${base64Encode(bytes)}';
}

/// Read back what [encodeMedia] wrote.
///
/// A file written before names were kept inside it holds nothing but base64,
/// and yields its bytes with no name. A header from a later version is still
/// read for its name, so long as the name is where this version puts it.
/// Throws [MediaEnvelopeException] when the content is neither.

MediaContent decodeMedia(String content) {
  final text = content.trimLeft();

  // A base64 alphabet has no brace in it, so a file that opens with one can
  // only have been written with a header.

  if (!text.startsWith('{')) {
    return (bytes: _decodeBase64(text), name: null);
  }

  final newline = text.indexOf('\n');
  if (newline < 0) {
    throw const MediaEnvelopeException('The media header has no content.');
  }

  final Object? header;
  try {
    header = jsonDecode(text.substring(0, newline));
  } on FormatException {
    throw const MediaEnvelopeException('The media header is not valid JSON.');
  }
  if (header is! Map<String, dynamic> || header['format'] != _marker) {
    throw const MediaEnvelopeException("The media header is not PhotoPod's.");
  }

  final name = header['name'];
  return (
    bytes: _decodeBase64(text.substring(newline + 1)),
    name: name is String && name.trim().isNotEmpty ? name : null,
  );
}

Uint8List _decodeBase64(String text) {
  try {
    return base64Decode(text.trim());
  } on FormatException {
    throw const MediaEnvelopeException('The media is not valid base64.');
  }
}
