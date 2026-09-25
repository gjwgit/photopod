/// Tests for the stored and displayed names of media files.
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

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/constants/media.dart';

void main() {
  group('storedNameOf', () {
    test('adds the suffix solidpod needs to encrypt a resource', () {
      expect(storedNameOf('beach.jpg'), 'beach.jpg.enc.ttl');
      expect(storedNameOf('clip.mp4'), 'clip.mp4.enc.ttl');
    });

    test('always ends in .ttl, which is what makes encryption possible', () {
      for (final name in ['a.jpg', 'a.png', 'a.tiff', 'a.mov']) {
        expect(storedNameOf(name).endsWith('.ttl'), isTrue, reason: name);
      }
    });
  });

  group('displayNameOf', () {
    test('hides the encryption suffix from the user', () {
      expect(displayNameOf('beach.jpg.enc.ttl'), 'beach.jpg');
      expect(displayNameOf('clip.mp4.enc.ttl'), 'clip.mp4');
    });

    test('leaves a plain resource name alone', () {
      expect(displayNameOf('beach.jpg'), 'beach.jpg');
      expect(displayNameOf('notes.ttl'), 'notes.ttl');
    });

    test('round trips with storedNameOf', () {
      for (final name in ['beach.jpg', 'my photo.png', 'a.b.c.mov']) {
        expect(displayNameOf(storedNameOf(name)), name, reason: name);
      }
    });
  });

  group('the section a stored file belongs to', () {
    test('is decided by the extension under the suffix', () {
      expect(kindOf(displayNameOf('beach.jpg.enc.ttl')), MediaKind.photo);
      expect(kindOf(displayNameOf('clip.mov.enc.ttl')), MediaKind.video);
    });

    test('is nothing for a stored name read without stripping', () {
      // A guard against listing files by their raw server name: the suffix
      // would make every photo look like an unsupported .ttl file.

      expect(kindOf('beach.jpg.enc.ttl'), isNull);
    });

    test('excludes an encrypted file that is not media', () {
      expect(kindOf(displayNameOf('notes.txt.enc.ttl')), isNull);
    });
  });
}
