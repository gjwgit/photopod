/// Tests for the dialogue that names a person.
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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:photopod/dialogs/person_dialogs.dart';
import 'package:photopod/models/face_book.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/people.dart';

PersonEntry _person() {
  const item = MediaItem(
    name: 'a.jpg',
    rawName: 'a.jpg',
    path: 'photopod/data/a.jpg',
    url: 'https://pod.example/photopod/data/a.jpg',
    isFolder: false,
  );
  final face = FaceRecord(
    id: 'a#0',
    path: item.path,
    box: const [0.1, 0.1, 0.5, 0.5],
    score: 0.95,
    embedding: Float32List(128),
    image: img.encodePng(img.Image(width: 4, height: 4)),
    person: 'p1',
  );
  return PersonEntry(
    id: 'p1',
    name: null,
    title: 'Unknown 7QK3',
    person: 'p1',
    portrait: face,
    portraitItem: item,
    items: const [item],
  );
}

void main() {
  // The dialogue used to dispose its controller as soon as it returned,
  // while its closing animation was still building the TextField.

  testWidgets('naming a person closes the dialogue cleanly', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showPersonNameDialog(context, _person()),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, 'Alice');
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
