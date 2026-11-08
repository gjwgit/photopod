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

void main() {
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
  });
}
