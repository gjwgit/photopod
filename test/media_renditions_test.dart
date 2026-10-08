/// Tests for the photo renditions PhotoPod keeps on the Pod.
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

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:photopod/models/photo_metadata.dart';
import 'package:photopod/services/media_renditions.dart';
import 'package:photopod/services/thumbnail_cache.dart';

Uint8List _jpeg(int width, int height) =>
    img.encodeJpg(img.Image(width: width, height: height));

int _longest(Uint8List bytes) {
  final image = img.decodeImage(bytes)!;
  return image.width > image.height ? image.width : image.height;
}

void main() {
  group('PhotoMetadata JSON', () {
    test('survives a round trip', () {
      final metadata = PhotoMetadata(
        width: 4032,
        height: 3024,
        taken: DateTime(2026, 9, 1, 10, 30),
        cameraMake: 'Apple',
        cameraModel: 'iPhone 15 Pro',
        exposureSeconds: 0.004,
        aperture: 1.8,
        iso: 50,
        latitude: -35.28,
        longitude: 149.13,
      );

      final back = PhotoMetadata.fromJson(
        jsonDecode(jsonEncode(metadata.toJson())) as Map<String, dynamic>,
      );

      expect(back.width, 4032);
      expect(back.taken, DateTime(2026, 9, 1, 10, 30));
      expect(back.cameraModel, 'iPhone 15 Pro');
      expect(back.iso, 50);
      expect(back.latitude, -35.28);
      expect(back.hasLocation, isTrue);
      expect(back.lens, isNull);
    });

    test('ignores values of the wrong type', () {
      final back = PhotoMetadata.fromJson({'width': 'wide', 'lens': 7});
      expect(back.isEmpty, isTrue);
    });
  });

  group('small rendition content', () {
    test('carries the picture and the details', () {
      final image = Uint8List.fromList([1, 2, 3]);
      final small = MediaRenditions.decodeSmall(
        MediaRenditions.encodeSmall(image, const PhotoMetadata(iso: 100)),
      );
      expect(small.image, image);
      expect(small.metadata?.iso, 100);
    });

    test('reads a first-build video thumbnail, a bare base64 JPEG', () {
      final small = MediaRenditions.decodeSmall(base64Encode([9, 8, 7]));
      expect(small.image, [9, 8, 7]);
      expect(small.metadata, isNull);
    });
  });

  group('renderPhoto', () {
    test('scales both renditions down to their sizes', () {
      final made = renderPhoto((
        bytes: _jpeg(3000, 2000),
        keepOriginal: false,
      ))!;
      expect(_longest(made.small), thumbnailSize);
      expect(_longest(made.large!), previewSize);
      expect(made.metadata?.width, 3000);
    });

    test('leaves a small photo at its own size', () {
      final made = renderPhoto((bytes: _jpeg(300, 200), keepOriginal: false))!;
      expect(_longest(made.small), 300);
      expect(_longest(made.large!), 300);
    });

    test('makes no large rendition when the original is to be kept', () {
      final made = renderPhoto((bytes: _jpeg(800, 600), keepOriginal: true))!;
      expect(made.large, isNull);
    });

    test('keeps transparency in the large rendition', () {
      final png = img.encodePng(
        img.Image(width: 50, height: 50, numChannels: 4),
      );
      final made = renderPhoto((bytes: png, keepOriginal: false))!;
      expect(img.findDecoderForData(made.large!), isA<img.PngDecoder>());
    });

    test('returns null for bytes that are not a picture', () {
      expect(
        renderPhoto((
          bytes: Uint8List.fromList([0, 1, 2]),
          keepOriginal: false,
        )),
        isNull,
      );
    });
  });
}
