/// Tests for the dialogues every Pod operation reports through.
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

import 'package:photopod/dialogs/message_dialog.dart';

Future<BuildContext> _host(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (each) {
          context = each;
          return const SizedBox();
        },
      ),
    ),
  );
  return context;
}

void main() {
  group('showWorking', () {
    testWidgets('goes away when the work is done at once', (tester) async {
      final context = await _host(tester);
      final result = await showWorking(context, 'Merging...', () async => 7);
      await tester.pumpAndSettle();
      expect(result, 7);
      expect(find.text('Merging...'), findsNothing);
    });

    testWidgets('goes away when the work takes a while', (tester) async {
      final context = await _host(tester);
      final working = showWorking(
        context,
        'Adding...',
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pump();
      expect(find.text('Adding...'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await working;
      await tester.pumpAndSettle();
      expect(find.text('Adding...'), findsNothing);
    });

    testWidgets('goes away when the work fails', (tester) async {
      final context = await _host(tester);
      await expectLater(
        showWorking(context, 'Failing...', () async => throw StateError('x')),
        throwsStateError,
      );
      await tester.pumpAndSettle();
      expect(find.text('Failing...'), findsNothing);
    });

    testWidgets('leaves a dialogue opened over it alone', (tester) async {
      final context = await _host(tester);
      final working = showWorking(
        context,
        'Adding...',
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pump();
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('On top')),
      );
      await tester.pump(const Duration(seconds: 2));
      await working;
      await tester.pumpAndSettle();
      expect(find.text('Adding...'), findsNothing);
      expect(find.text('On top'), findsOneWidget);
    });
  });
}
