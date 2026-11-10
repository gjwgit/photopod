/// Tests for reading the faces the Analyser finds.
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
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/models/face_book.dart';
import 'package:photopod/services/face_results.dart';

void main() {
  // assets/demo/faces.json is what analyser/face_analyser answered for the
  // sample photos, so it doubles as a record of the service's format.

  final demo =
      jsonDecode(File('assets/demo/faces.json').readAsStringSync())
          as Map<String, dynamic>;
  final faces = demo['faces'] as Map<String, dynamic>;

  test('the service describes faces with the models PhotoPod files by', () {
    expect(demo['model'], faceModelId);
  });

  test('each face is read as the engine hands it to FaceBook', () {
    final found = parseFoundFaces(faces['john_mather_2012.jpg'] as List);
    expect(found, hasLength(1));
    final face = found.single;
    expect(face.box, hasLength(4));
    expect(face.box.every((v) => v >= 0 && v <= 1), isTrue);
    expect(face.score, greaterThanOrEqualTo(0.6));
    expect(face.embedding, hasLength(512));
    final norm = face.embedding.fold<double>(0, (sum, v) => sum + v * v);
    expect(norm, closeTo(1, 1e-4));
    expect(face.image!.sublist(0, 2), [0xff, 0xd8]);
  });

  test('the service\'s faces group the samples by who is in them', () {
    final book = FaceBook();
    for (final entry in faces.entries) {
      book.addPhoto(entry.key, parseFoundFaces(entry.value as List));
    }

    // Each laureate's photos are named after them, so the people found
    // should split the photos along those names and nowhere else.

    final groups = {
      for (final person in book.people.values)
        {
          for (final face in book.facesOf(person.id))
            face.path.split('_').take(2).join('_'),
        },
    };
    expect(groups, hasLength(3));
    expect(groups.every((names) => names.length == 1), isTrue);
  });
}
