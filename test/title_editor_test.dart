/// Tests for the editable title of a photo.
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

import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/widgets/title_editor.dart';

Future<List<String>> _pump(WidgetTester tester, PhotoTitle? title) async {
  final changes = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TitleEditor(title: title, onChanged: changes.add),
            const TextField(key: Key('elsewhere')),
          ],
        ),
      ),
    ),
  );
  return changes;
}

void main() {
  testWidgets('shows the title the photo has', (tester) async {
    await _pump(tester, const PhotoTitle('Bondi'));
    expect(find.text('Bondi'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
  });

  testWidgets('marks a suggested title and who suggested it', (tester) async {
    await _pump(tester, const PhotoTitle('A beach', source: 'teepod:vision'));
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(
      find.text('Suggested by teepod:vision. Edit it to make it yours.'),
      findsOneWidget,
    );
  });

  testWidgets('saves what is typed when Enter is pressed', (tester) async {
    final changes = await _pump(tester, null);
    await tester.enterText(find.byType(TitleEditor), '  Sunset ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(changes, ['Sunset']);
  });

  testWidgets('saves when the user moves on', (tester) async {
    final changes = await _pump(tester, null);
    await tester.enterText(find.byType(TitleEditor), 'Sunset');
    await tester.tap(find.byKey(const Key('elsewhere')));
    await tester.pump();
    expect(changes, ['Sunset']);
  });

  testWidgets('saves nothing when the title is unchanged', (tester) async {
    final changes = await _pump(tester, const PhotoTitle('Bondi'));
    await tester.enterText(find.byType(TitleEditor), ' Bondi ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(changes, isEmpty);
  });

  testWidgets('saves an empty title, which takes it away', (tester) async {
    final changes = await _pump(tester, const PhotoTitle('Bondi'));
    await tester.enterText(find.byType(TitleEditor), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(changes, ['']);
  });

  testWidgets('keeps a title typed just before it is closed', (tester) async {
    final changes = await _pump(tester, null);
    await tester.enterText(find.byType(TitleEditor), 'Sunset');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(changes, ['Sunset']);
  });
}
