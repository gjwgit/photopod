/// Tests for reading a photo's own EXIF details.
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

import 'package:photopod/models/photo_metadata.dart';

void main() {
  group('dmsToDegrees', () {
    test('converts a northern latitude', () {
      // 35 degrees, 16 minutes, 51.2 seconds north.

      final degrees = dmsToDegrees(35, 16, 51.2, 'N', limit: 90);
      expect(degrees, closeTo(35.2809, 0.0001));
    });

    test('makes a southern latitude negative', () {
      final degrees = dmsToDegrees(35, 16, 51.2, 'S', limit: 90);
      expect(degrees, closeTo(-35.2809, 0.0001));
    });

    test('makes a western longitude negative', () {
      final degrees = dmsToDegrees(149, 7, 48, 'W', limit: 180);
      expect(degrees, closeTo(-149.13, 0.0001));
    });

    test('rejects a value outside the range the Earth offers', () {
      expect(dmsToDegrees(300, 0, 0, 'N', limit: 90), isNull);
      expect(dmsToDegrees(190, 0, 0, 'E', limit: 180), isNull);
    });

    test('rejects the all-zero reading a camera writes with no fix', () {
      expect(dmsToDegrees(0, 0, 0, 'N', limit: 90), isNull);
    });

    test('treats a missing hemisphere as positive', () {
      expect(dmsToDegrees(10, 30, 0, null, limit: 90), closeTo(10.5, 0.0001));
    });

    test('rejects values that are not numbers', () {
      expect(dmsToDegrees(double.nan, 0, 0, 'N', limit: 90), isNull);
      expect(dmsToDegrees(1, double.infinity, 0, 'N', limit: 90), isNull);
    });
  });

  group('parseExifDateTime', () {
    test('reads the colon-separated stamp a camera writes', () {
      expect(
        parseExifDateTime('2026:09:22 14:05:33'),
        DateTime(2026, 9, 22, 14, 5, 33),
      );
    });

    test('copes with a stamp that has no seconds', () {
      expect(
        parseExifDateTime('2026:09:22 14:05'),
        DateTime(2026, 9, 22, 14, 5),
      );
    });

    test('rejects the zero stamp of a camera whose clock was never set', () {
      expect(parseExifDateTime('0000:00:00 00:00:00'), isNull);
    });

    test('rejects nonsense and nothing at all', () {
      expect(parseExifDateTime(null), isNull);
      expect(parseExifDateTime(''), isNull);
      expect(parseExifDateTime('last Tuesday'), isNull);
    });
  });

  group('formatShutterSpeed', () {
    test('writes a fast shutter as a fraction', () {
      expect(formatShutterSpeed(0.004), '1/250 s');
    });

    test('writes a slow shutter as a number of seconds', () {
      expect(formatShutterSpeed(2), '2 s');
      expect(formatShutterSpeed(1.5), '1.5 s');
    });
  });

  group('formatCoordinate', () {
    test('spells out the hemisphere', () {
      expect(formatCoordinate(-35.2809, 'N', 'S'), '35.2809° S');
      expect(formatCoordinate(149.13, 'E', 'W'), '149.1300° E');
    });
  });

  group('PhotoMetadata', () {
    test('does not repeat the make when the model already carries it', () {
      const metadata = PhotoMetadata(
        cameraMake: 'Apple',
        cameraModel: 'Apple iPhone 15 Pro',
      );
      expect(metadata.camera, 'Apple iPhone 15 Pro');
    });

    test('joins a make and model that do not overlap', () {
      const metadata = PhotoMetadata(cameraMake: 'NIKON', cameraModel: 'Z 6');
      expect(metadata.camera, 'NIKON Z 6');
    });

    test('gathers the exposure into one line', () {
      const metadata = PhotoMetadata(
        exposureSeconds: 0.004,
        aperture: 1.8,
        focalLength: 26,
        iso: 64,
      );
      expect(metadata.exposure, '1/250 s  ·  f/1.8  ·  26 mm  ·  ISO 64');
    });

    test('has a location only when both coordinates are there', () {
      expect(const PhotoMetadata(latitude: -35.28).hasLocation, isFalse);
      expect(
        const PhotoMetadata(latitude: -35.28, longitude: 149.13).hasLocation,
        isTrue,
      );
    });

    test('is empty when the photo said nothing about itself', () {
      expect(const PhotoMetadata().isEmpty, isTrue);
      expect(const PhotoMetadata(iso: 100).isEmpty, isFalse);
    });

    test('keeps everything else when the size is filled in', () {
      const metadata = PhotoMetadata(cameraModel: 'Z 6', iso: 400);
      final sized = metadata.copyWithSize(width: 6000, height: 4000);

      expect(sized.width, 6000);
      expect(sized.height, 4000);
      expect(sized.cameraModel, 'Z 6');
      expect(sized.iso, 400);
    });
  });
}
