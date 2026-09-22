/// Tests for the browser widgets.
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

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/view_prefs.dart';
import 'package:photopod/widgets/breadcrumb_bar.dart';
import 'package:photopod/widgets/media_grid.dart';
import 'package:photopod/widgets/media_list.dart';
import 'package:photopod/widgets/media_toolbar.dart';
import 'package:photopod/widgets/pagination_bar.dart';

MediaItem _item(String name, {bool isFolder = false, int? size}) => MediaItem(
  name: name,
  rawName: name,
  path: 'photopod/data/$name',
  url: 'https://pod.example/photopod/data/$name',
  isFolder: isFolder,
  size: size,
  modified: DateTime(2026, 9, 22, 14, 5),
);

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 900, child: child)),
);

MediaActions _actions({VoidCallback? onDelete}) => MediaActions(
  onAddFiles: () {},
  onNewFolder: () {},
  onDelete: onDelete ?? () {},
  onCopy: () {},
  onMove: () {},
  onRename: () {},
  onShare: () {},
  onView: () {},
  onPreview: () {},
  onRefresh: () {},
  onSort: (_) {},
);

void main() {
  group('MediaGrid', () {
    testWidgets('names every item it is given', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MediaGrid(
            items: [_item('holiday', isFolder: true), _item('beach.jpg')],
            isSelected: (_) => false,
            onTap: (_) {},
            onActivate: (_) {},
          ),
        ),
      );

      expect(find.text('holiday'), findsOneWidget);
      expect(find.text('beach.jpg'), findsOneWidget);
    });

    testWidgets('truncates a name too long for its tile', (tester) async {
      const long = 'an-extremely-long-photograph-file-name-from-a-camera.jpg';
      await tester.pumpWidget(
        _wrap(
          MediaGrid(
            items: [_item(long)],
            isSelected: (_) => false,
            onTap: (_) {},
            onActivate: (_) {},
          ),
        ),
      );

      final text = tester.widget<Text>(find.text(long));
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, 1);
    });

    testWidgets('reports taps and double taps separately', (tester) async {
      MediaItem? tapped;
      MediaItem? activated;

      await tester.pumpWidget(
        _wrap(
          MediaGrid(
            items: [_item('beach.jpg')],
            isSelected: (_) => false,
            onTap: (item) => tapped = item,
            onActivate: (item) => activated = item,
          ),
        ),
      );

      await tester.tap(find.text('beach.jpg'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tapped?.name, 'beach.jpg');
      expect(activated, isNull);

      await tester.tap(find.text('beach.jpg'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('beach.jpg'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(activated?.name, 'beach.jpg');
    });
  });

  group('MediaList', () {
    testWidgets('shows the size and date beside the name', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MediaList(
            items: [_item('beach.jpg', size: 204800)],
            isSelected: (_) => false,
            onTap: (_) {},
            onActivate: (_) {},
          ),
        ),
      );

      expect(find.text('beach.jpg'), findsOneWidget);
      expect(find.text('200 KB'), findsOneWidget);
      expect(find.text('2026-09-22 14:05'), findsOneWidget);
      expect(find.text('JPG file'), findsOneWidget);
    });
  });

  group('MediaToolbar', () {
    testWidgets('disables the selection actions when nothing is selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MediaToolbar(
            kind: MediaKind.photo,
            selectionCount: 0,
            canPreview: false,
            sortOption: MediaSortOption.nameAscending,
            actions: _actions(),
          ),
        ),
      );

      for (final icon in [
        Icons.delete_outline,
        Icons.content_copy,
        Icons.drive_file_move_outline,
        Icons.drive_file_rename_outline,
        Icons.share_outlined,
        Icons.visibility_outlined,
      ]) {
        final button = tester.widget<IconButton>(
          find.ancestor(
            of: find.byIcon(icon),
            matching: find.byType(IconButton),
          ),
        );
        expect(button.onPressed, isNull, reason: '$icon');
      }
    });

    testWidgets('enables Delete once something is selected', (tester) async {
      var deleted = false;

      await tester.pumpWidget(
        _wrap(
          MediaToolbar(
            kind: MediaKind.photo,
            selectionCount: 2,
            canPreview: true,
            sortOption: MediaSortOption.nameAscending,
            actions: _actions(onDelete: () => deleted = true),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      expect(deleted, isTrue);
    });
  });

  group('PaginationBar', () {
    testWidgets('hides the page controls for a single page', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PaginationBar(
            page: 0,
            pageCount: 1,
            total: 3,
            shown: 3,
            selected: 0,
            onPage: (_) {},
          ),
        ),
      );

      expect(find.text('3 of 3 shown'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('steps forward a page and reports the selection', (
      tester,
    ) async {
      int? requested;

      await tester.pumpWidget(
        _wrap(
          PaginationBar(
            page: 0,
            pageCount: 3,
            total: 60,
            shown: 20,
            selected: 2,
            onPage: (page) => requested = page,
          ),
        ),
      );

      expect(find.text('20 of 60 shown  ·  2 selected'), findsOneWidget);
      expect(find.text('Page 1 of 3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      expect(requested, 1);
    });
  });

  group('BreadcrumbBar', () {
    testWidgets('makes every step but the last one a link', (tester) async {
      int? kept;

      await tester.pumpWidget(
        _wrap(
          BreadcrumbBar(
            segments: const ['holiday', '2026'],
            onNavigate: (keep) => kept = keep,
            onUp: () {},
          ),
        ),
      );

      expect(find.text('holiday'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);

      await tester.tap(find.text('holiday'));
      await tester.pump();
      expect(kept, 1);
    });

    testWidgets('cannot go up from the root', (tester) async {
      await tester.pumpWidget(
        _wrap(
          BreadcrumbBar(segments: const [], onNavigate: (_) {}, onUp: null),
        ),
      );

      final up = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.arrow_upward),
          matching: find.byType(IconButton),
        ),
      );
      expect(up.onPressed, isNull);
    });
  });
}
