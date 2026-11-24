/// Tests for choosing between TeePod and the Solid Community analyser.
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

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:photopod/dialogs/analyser_choice_dialog.dart';
import 'package:photopod/models/analyser_choice.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nothing is chosen until the user chooses', () async {
    final choice = AnalyserChoice();
    await choice.load();
    expect(choice.chosen, isNull);
  });

  test('the choice is remembered on the device', () async {
    await AnalyserChoice().choose(AnalyserBackend.solidCommunity);

    final again = AnalyserChoice();
    await again.load();
    expect(again.chosen, AnalyserBackend.solidCommunity);
  });

  test('a stored name no longer known is taken as no choice', () async {
    SharedPreferences.setMockInitialValues({'photopod.analyser': 'gone'});
    final choice = AnalyserChoice();
    await choice.load();
    expect(choice.chosen, isNull);
  });

  testWidgets('the dialogue says how private each analyser is', (
    tester,
  ) async {
    // Tall enough for the whole dialogue, so that both options can be tapped.

    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final choice = AnalyserChoice();
    AnalyserBackend? picked;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: choice,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  picked = await showAnalyserChoiceDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('TeePod'), findsOneWidget);
    expect(find.text('Higher privacy'), findsOneWidget);
    expect(find.text('Solid Community'), findsOneWidget);
    expect(find.text('Limited privacy'), findsOneWidget);

    await tester.tap(find.text('Solid Community'));
    await tester.pump();
    await tester.tap(find.text('Use this analyser'));
    await tester.pumpAndSettle();

    expect(picked, AnalyserBackend.solidCommunity);
    expect(choice.chosen, AnalyserBackend.solidCommunity);
  });
}
