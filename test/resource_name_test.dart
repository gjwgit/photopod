/// Tests for the names PhotoPod gives resources on the Pod.
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
import 'package:photopod/utils/resource_name.dart';

void main() {
  group('safeResourceName', () {
    test('leaves a name that needs no escaping alone', () {
      for (final name in [
        'DSC03274_colcorrected_NB.jpg',
        'beach.jpg',
        'holiday-2026.mp4',
        "don't.png",
        'clip(2).mov',
        'a~b!c.jpg',
      ]) {
        expect(safeResourceName(name), name, reason: name);
      }
    });

    test('replaces a space, which would otherwise be escaped', () {
      expect(safeResourceName('my photo.jpg'), 'my_photo.jpg');
    });

    test('replaces a run of awkward characters with one underscore', () {
      expect(safeResourceName('holiday #1 (50%).jpg'), 'holiday_1_(50_).jpg');
    });

    test('replaces characters no file system would take', () {
      expect(safeResourceName('a/b.jpg'), 'a_b.jpg');
      expect(safeResourceName(r'a\b.jpg'), 'a_b.jpg');
      expect(safeResourceName('a:b*c?.jpg'), 'a_b_c_.jpg');
    });

    test('keeps the extension, so the file stays a photo or a video', () {
      for (final name in ['我的照片.jpg', 'ünïcödé.png', 'ролик.mp4']) {
        expect(kindOf(safeResourceName(name)), kindOf(name), reason: name);
      }
    });

    test('gives a stem to a name that is left with only its extension', () {
      expect(safeResourceName('我的照片.jpg'), 'file.jpg');
      expect(safeResourceName('   .png'), 'file.png');
    });

    test('leaves a name that deliberately begins with a full stop', () {
      expect(safeResourceName('...odd.jpg'), '...odd.jpg');
    });

    test('never returns an empty name', () {
      expect(safeResourceName('///'), 'file');
      expect(safeResourceName(''), 'file');
    });
  });

  group('isSafeResourceName', () {
    test('agrees with what safeResourceName leaves alone', () {
      for (final name in [
        'beach.jpg',
        'my photo.jpg',
        '我的照片.jpg',
        'a*b.jpg',
        'a%20b.jpg',
      ]) {
        expect(
          isSafeResourceName(name),
          safeResourceName(name) == name,
          reason: name,
        );
      }
    });

    test('an empty name is not usable', () {
      expect(isSafeResourceName(''), isFalse);
    });
  });

  group('the round trip solidpod makes through a URL', () {
    // solidpod takes a resource's path back out of its URL with
    // `Uri.pathSegments`, which decodes each segment, and rebuilds the URL by
    // joining the segments verbatim, which does not encode them again. A name
    // that survives that round trip unchanged keeps its encryption key; a
    // name that does not, loses it. Every name PhotoPod writes must survive.

    String roundTrip(String url) {
      final segments = Uri.parse(url).pathSegments;
      return 'https://pod.example/${segments.join('/')}';
    }

    test('a safe name survives it', () {
      for (final name in [
        'DSC03274_colcorrected_NB.jpg',
        'holiday_1_(50_).jpg',
        "don't-2026.mp4",
      ]) {
        final url = 'https://pod.example/me/photopod/data/$name.enc.ttl';
        expect(roundTrip(url), url, reason: name);
      }
    });

    test(
      'an escaped name does not, which is the bug being guarded against',
      () {
        const url =
            'https://pod.example/me/photopod/data/my%20photo.jpg.enc.ttl';
        expect(roundTrip(url), isNot(url));
      },
    );

    test('every sanitised name survives it', () {
      for (final original in [
        'my photo.jpg',
        'holiday #1 (50%).jpg',
        '我的照片.jpg',
        'a+b&c=d.png',
        'photo@home,2026.jpg',
      ]) {
        final name = safeResourceName(original);
        final url = 'https://pod.example/me/photopod/data/$name.enc.ttl';
        expect(roundTrip(url), url, reason: original);
      }
    });
  });
}
