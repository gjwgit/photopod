/// Tests for the editable row of tags or people on a photo.
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
/// Authors: Graham Williams

library;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/models/catalog_entry.dart' show userSource;
import 'package:photopod/widgets/label_editor.dart';

Future<({List<String> added, List<int> removed})> _pump(
  WidgetTester tester, {
  List<PhotoLabel> labels = const [],
  List<String> suggestions = const [],
}) async {
  final added = <String>[];
  final removed = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LabelEditor(
          labels: labels,
          suggestions: suggestions,
          hint: 'Add a tag',
          icon: Icons.sell_outlined,
          onAdd: added.add,
          onRemove: removed.add,
        ),
      ),
    ),
  );
  return (added: added, removed: removed);
}

void main() {
  testWidgets('shows each label as a chip', (tester) async {
    await _pump(
      tester,
      labels: [
        (text: 'beach', source: userSource, confidence: null),
        (text: 'ocean', source: 'teepod:vision', confidence: 0.93),
      ],
    );
    expect(find.widgetWithText(InputChip, 'beach'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'ocean'), findsOneWidget);
  });

  testWidgets('marks only a suggested label with a sparkle', (tester) async {
    await _pump(
      tester,
      labels: [
        (text: 'beach', source: userSource, confidence: null),
        (text: 'ocean', source: 'teepod:vision', confidence: 0.93),
      ],
    );
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(
      find.byTooltip(
        'Suggested by teepod:vision (93% sure). Take it off if it is wrong.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('adds what is typed when Enter is pressed', (tester) async {
    final calls = await _pump(tester);
    await tester.enterText(find.byType(TextField), '  sunset ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(calls.added, ['sunset']);
    expect(find.text('  sunset '), findsNothing);
  });

  testWidgets('adds nothing for an empty field', (tester) async {
    final calls = await _pump(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(calls.added, isEmpty);
  });

  testWidgets('takes a label off with its cross', (tester) async {
    final calls = await _pump(
      tester,
      labels: [
        (text: 'beach', source: userSource, confidence: null),
        (text: 'ocean', source: userSource, confidence: null),
      ],
    );
    await tester.tap(find.byTooltip('Remove "ocean"'));
    expect(calls.removed, [1]);
  });

  testWidgets('offers labels used before, but not those already here', (
    tester,
  ) async {
    final calls = await _pump(
      tester,
      labels: [(text: 'Beach', source: userSource, confidence: null)],
      suggestions: ['beach', 'Beach house', 'mountain'],
    );
    await tester.enterText(find.byType(TextField), 'bea');
    await tester.pumpAndSettle();
    expect(find.text('Beach house'), findsOneWidget);
    expect(find.text('mountain'), findsNothing);
    expect(find.widgetWithText(InkWell, 'beach'), findsNothing);

    await tester.tap(find.text('Beach house'));
    await tester.pumpAndSettle();
    expect(calls.added, ['Beach house']);
    expect(find.text('bea'), findsNothing);
  });
}
