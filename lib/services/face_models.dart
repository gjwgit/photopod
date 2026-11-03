/// The two ONNX models face recognition runs on, fetched once per device.
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

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// One model file: where it comes from, and the SHA-256 it must have, so
/// that a truncated or tampered download is never loaded.

class FaceModel {
  final String fileName;
  final String url;
  final String sha256;

  const FaceModel(this.fileName, this.url, this.sha256);
}

const _zoo = 'https://github.com/opencv/opencv_zoo/raw/main/models';

/// YuNet, OpenCV's face detector (MIT licence, 0.2 MB). It finds each face
/// and the five landmarks the recogniser aligns it by.

const detectorModel = FaceModel(
  'face_detection_yunet_2023mar.onnx',
  '$_zoo/face_detection_yunet/face_detection_yunet_2023mar.onnx',
  '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4',
);

/// SFace, OpenCV's face recogniser (Apache 2.0 licence, 37 MB). It turns an
/// aligned face into 128 numbers that lie close together for one person.

const recogniserModel = FaceModel(
  'face_recognition_sface_2021dec.onnx',
  '$_zoo/face_recognition_sface/face_recognition_sface_2021dec.onnx',
  '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
);

/// The local paths of both models, downloading whichever is missing.
///
/// They are kept in the application support folder rather than shipped with
/// the app, since only someone who opens People needs the 37 MB recogniser.
/// [onDownload] is told before a download starts.

Future<({String detector, String recogniser})> ensureFaceModels({
  void Function(FaceModel model)? onDownload,
}) async {
  final folder = Directory(
    '${(await getApplicationSupportDirectory()).path}/face_models',
  );
  await folder.create(recursive: true);

  Future<String> ensure(FaceModel model) async {
    final file = File('${folder.path}/${model.fileName}');
    if (await file.exists()) return file.path;

    onDownload?.call(model);
    final response = await http.get(Uri.parse(model.url));
    if (response.statusCode != 200) {
      throw HttpException(
        'Could not download ${model.fileName} (${response.statusCode}).',
      );
    }
    if (sha256.convert(response.bodyBytes).toString() != model.sha256) {
      throw HttpException('${model.fileName} did not download intact.');
    }

    // Written beside the final name and then renamed, so that an
    // interrupted write never leaves a partial model to be loaded next time.

    final partial = File('${file.path}.part');
    await partial.writeAsBytes(response.bodyBytes, flush: true);
    await partial.rename(file.path);
    return file.path;
  }

  return (
    detector: await ensure(detectorModel),
    recogniser: await ensure(recogniserModel),
  );
}
