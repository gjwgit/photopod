/// Face detection and recognition through OpenCV, on a background isolate.
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

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'package:photopod/models/face_book.dart';
import 'package:photopod/services/face_models.dart';

/// How sure YuNet must be before a face counts. Its own default, which keeps
/// patterned fabric and the faces on posters out of People.

const double _minScore = 0.9;

/// The smallest face, in pixels of the picture analysed, worth recognising.
/// Below this SFace has too little to go on: a face 18 pixels high matched
/// itself at only 0.52 in testing, close enough to the threshold to drift.

const int _minFaceSide = 32;

/// The longest side a picture is analysed at. The large rendition is already
/// this size; an original without one is brought down to it.

const int _maxSide = 2048;

/// The side, in pixels, of the square picture kept of each face: sharp for
/// the portraits People shows, small enough that a few hundred faces add
/// only a megabyte or so to the faces file.

const int _faceImageSide = 96;

/// How much room is left around a face in its picture, as a multiple of the
/// face's size, so that the picture shows the head rather than the features.

const double _faceImageMargin = 1.6;

// The functions face_engine.dart calls, matched by face_engine_stub.dart.

bool faceEngineSupported() => true;

Future<void> startFaceEngine({void Function(String)? onStatus}) =>
    _Engine.start(onStatus: onStatus);

Future<List<FoundFace>> analyseFaces(Uint8List image) => _Engine.analyse(image);

void stopFaceEngine() => _Engine.stop();

/// The face engine: YuNet finds the faces, SFace describes each one.
///
/// Both models stay loaded in one long-lived isolate, since loading the
/// 37 MB recogniser takes far longer than analysing a photo with it (about
/// 10 to 40 ms on a laptop), and since OpenCV's calls would otherwise hold
/// up the frames being drawn.

class _Engine {
  const _Engine._();

  static SendPort? _worker;
  static Future<void>? _starting;
  static Isolate? _isolate;
  static ReceivePort? _replies;
  static int _nextId = 0;
  static final Map<int, Completer<List<FoundFace>>> _pending = {};

  /// Fetch the models if need be and start the worker. [onStatus] hears
  /// what is happening, for the status line.

  static Future<void> start({void Function(String)? onStatus}) =>
      _starting ??= _start(onStatus).catchError((Object e) {
        _starting = null;
        throw e;
      });

  static Future<void> _start(void Function(String)? onStatus) async {
    final models = await ensureFaceModels(
      onDownload: (model) => onStatus?.call('Downloading ${model.fileName}...'),
    );
    onStatus?.call('Loading the face models...');

    final replies = ReceivePort();
    final ready = Completer<SendPort>();
    replies.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is (int, List<FoundFace>?, String?)) {
        final (id, faces, error) = message;
        final pending = _pending.remove(id);
        if (pending == null) return;
        error == null
            ? pending.complete(faces!)
            : pending.completeError(StateError(error));
      } else if (message is String && !ready.isCompleted) {
        ready.completeError(StateError(message));
      }
    });

    _replies = replies;
    _isolate = await Isolate.spawn(_workerMain, (
      replies.sendPort,
      models.detector,
      models.recogniser,
    ));
    _worker = await ready.future;
  }

  /// The faces in [image], an encoded JPEG, PNG or similar.

  static Future<List<FoundFace>> analyse(Uint8List image) async {
    await start();
    final id = _nextId++;
    final reply = _pending[id] = Completer<List<FoundFace>>();
    _worker!.send((id, TransferableTypedData.fromList([image])));
    return reply.future;
  }

  /// Shut the worker down, as on logout. It starts again when next needed.

  static void stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _replies?.close();
    for (final pending in _pending.values) {
      pending.completeError(StateError('The face engine was stopped.'));
    }
    _pending.clear();
    _isolate = null;
    _replies = null;
    _worker = null;
    _starting = null;
  }
}

void _workerMain((SendPort, String, String) setup) {
  final (replies, detectorPath, recogniserPath) = setup;

  final cv.FaceDetectorYN detector;
  final cv.FaceRecognizerSF recogniser;
  try {
    detector = cv.FaceDetectorYN.fromFile(detectorPath, '', (
      320,
      320,
    ), scoreThreshold: _minScore);
    recogniser = cv.FaceRecognizerSF.fromFile(recogniserPath, '');
  } on Object catch (e) {
    replies.send('Could not load the face models: $e');
    return;
  }

  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((message) {
    final (id, data) = message as (int, TransferableTypedData);
    try {
      final bytes = data.materialize().asUint8List();
      replies.send((id, _analyse(detector, recogniser, bytes), null));
    } on Object catch (e) {
      replies.send((id, null, '$e'));
    }
  });
}

List<FoundFace> _analyse(
  cv.FaceDetectorYN detector,
  cv.FaceRecognizerSF recogniser,
  Uint8List bytes,
) {
  // IMREAD_COLOR applies the EXIF orientation, so an original is analysed
  // the way up it is shown, as the renditions already are.

  var image = cv.imdecode(bytes, cv.IMREAD_COLOR);
  if (image.isEmpty) return const [];

  final longest = math.max(image.cols, image.rows);
  if (longest > _maxSide) {
    final scale = _maxSide / longest;
    final smaller = cv.resize(image, (
      (image.cols * scale).round(),
      (image.rows * scale).round(),
    ), interpolation: cv.INTER_AREA);
    image.dispose();
    image = smaller;
  }

  final width = image.cols.toDouble();
  final height = image.rows.toDouble();
  detector.setInputSize((image.cols, image.rows));
  final detections = detector.detect(image);

  // Each row is x, y, width, height, five landmarks as x, y pairs, and the
  // score.

  final found = <FoundFace>[];
  for (var row = 0; row < detections.rows; row++) {
    final w = detections.at<double>(row, 2);
    final h = detections.at<double>(row, 3);
    if (math.min(w, h) < _minFaceSide) continue;

    final face = detections.row(row);
    final aligned = recogniser.alignCrop(image, face);
    final feature = recogniser.feature(aligned, clone: true);
    found.add((
      box: [
        detections.at<double>(row, 0) / width,
        detections.at<double>(row, 1) / height,
        w / width,
        h / height,
      ],
      score: detections.at<double>(row, 14),
      embedding: _unitLength(feature),
      image: _faceImage(image, row, detections),
    ));
    feature.dispose();
    aligned.dispose();
    face.dispose();
  }

  detections.dispose();
  image.dispose();
  return found;
}

Float32List _unitLength(cv.Mat feature) {
  final values = Float32List(feature.cols);
  var norm = 0.0;
  for (var i = 0; i < values.length; i++) {
    values[i] = feature.at<double>(0, i);
    norm += values[i] * values[i];
  }
  norm = math.sqrt(norm);
  if (norm > 0) {
    for (var i = 0; i < values.length; i++) {
      values[i] /= norm;
    }
  }
  return values;
}

// A square JPEG of the face in [row] of [detections], with some room around
// it, cut from [image] and scaled to [_faceImageSide].

Uint8List? _faceImage(cv.Mat image, int row, cv.Mat detections) {
  final x = detections.at<double>(row, 0);
  final y = detections.at<double>(row, 1);
  final w = detections.at<double>(row, 2);
  final h = detections.at<double>(row, 3);

  final side = math
      .min(math.max(w, h) * _faceImageMargin, math.min(image.cols, image.rows))
      .floor();
  final left = (x + w / 2 - side / 2).clamp(0, image.cols - side).floor();
  final top = (y + h / 2 - side / 2).clamp(0, image.rows - side).floor();

  final region = image.region(cv.Rect(left, top, side, side));
  final small = cv.resize(region, (
    _faceImageSide,
    _faceImageSide,
  ), interpolation: cv.INTER_AREA);
  final (ok, jpeg) = cv.imencode(
    '.jpg',
    small,
    params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 85]),
  );
  small.dispose();
  region.dispose();
  return ok ? jpeg : null;
}
