/// Tests for the widgets the album is drawn with.
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

import 'package:photopod/models/library_section.dart';
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

MediaActions _actions({
  VoidCallback? onDelete,
  VoidCallback? onGetInfo,
  VoidCallback? onToggleFavourite,
}) => MediaActions(
  onAddFiles: () {},
  onNewFolder: () {},
  onDelete: onDelete ?? () {},
  onCopy: () {},
  onMove: () {},
  onRename: () {},
  onShare: () {},
  onView: () {},
  onPreview: () {},
  onGetInfo: onGetInfo ?? () {},
  onToggleFavourite: onToggleFavourite ?? () {},
  onRefresh: () {},
  onSort: (_) {},
);

Widget _grid(
  List<MediaItem> items, {
  bool Function(MediaItem)? isFavourite,
  void Function(MediaItem)? onTap,
  void Function(MediaItem)? onActivate,
  void Function(MediaItem)? onToggleFavourite,
}) => MediaGrid(
  items: items,
  isSelected: (_) => false,
  isFavourite: isFavourite ?? (_) => false,
  onTap: onTap ?? (_) {},
  onActivate: onActivate ?? (_) {},
  onToggleFavourite: onToggleFavourite ?? (_) {},
);

void main() {
  group('MediaGrid', () {
    testWidgets('draws a tile for every item it is given', (tester) async {
      await tester.pumpWidget(
        _wrap(_grid([_item('holiday', isFolder: true), _item('beach.jpg')])),
      );

      expect(find.byType(MediaTile), findsNWidgets(2));
    });

    testWidgets('names folders but not photos', (tester) async {
      await tester.pumpWidget(
        _wrap(_grid([_item('holiday', isFolder: true), _item('beach.jpg')])),
      );

      // A folder tile with no name would say nothing at all, so folders keep
      // their label. A photo speaks for itself and its name is left to the
      // tooltip and to Get Info.

      expect(find.text('holiday'), findsOneWidget);
      expect(find.text('beach.jpg'), findsNothing);
    });

    testWidgets('reports taps and double taps separately', (tester) async {
      MediaItem? tapped;
      MediaItem? activated;

      await tester.pumpWidget(
        _wrap(
          _grid(
            [_item('beach.jpg')],
            onTap: (item) => tapped = item,
            onActivate: (item) => activated = item,
          ),
        ),
      );

      await tester.tap(find.byType(MediaTile));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tapped?.name, 'beach.jpg');
      expect(activated, isNull);

      await tester.tap(find.byType(MediaTile));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(MediaTile));
      await tester.pump(const Duration(milliseconds: 400));
      expect(activated?.name, 'beach.jpg');
    });

    testWidgets('shows a filled heart on a favourite and reports a tap', (
      tester,
    ) async {
      MediaItem? hearted;

      await tester.pumpWidget(
        _wrap(
          _grid(
            [_item('beach.jpg')],
            isFavourite: (_) => true,
            onToggleFavourite: (item) => hearted = item,
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite), findsOneWidget);

      // The tile listens for a double tap too, so the heart's own tap is only
      // settled once the gesture arena has given up waiting for a second one.

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pump(const Duration(milliseconds: 400));
      expect(hearted?.name, 'beach.jpg');
    });

    testWidgets('keeps the heart off a tile that has none', (tester) async {
      await tester.pumpWidget(_wrap(_grid([_item('beach.jpg')])));

      // The heart appears on hover, when the tile is selected, or when it is
      // already a favourite, so a plain unselected tile stays clean.

      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    });

    testWidgets('badges a video so it is told apart from a photo', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_grid([_item('holiday.mp4'), _item('beach.jpg')])),
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });
  });

  group('MediaList', () {
    testWidgets('shows the size and date beside the name', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MediaList(
            items: [_item('beach.jpg', size: 204800)],
            isSelected: (_) => false,
            isFavourite: (_) => false,
            onTap: (_) {},
            onActivate: (_) {},
            onToggleFavourite: (_) {},
          ),
        ),
      );

      expect(find.text('beach.jpg'), findsOneWidget);
      expect(find.text('200 KB'), findsOneWidget);
      expect(find.text('2026-09-22 14:05'), findsOneWidget);
      expect(find.text('JPG file'), findsOneWidget);
    });

    testWidgets('offers a heart on every file', (tester) async {
      MediaItem? hearted;

      await tester.pumpWidget(
        _wrap(
          MediaList(
            items: [_item('holiday', isFolder: true), _item('beach.jpg')],
            isSelected: (_) => false,
            isFavourite: (_) => false,
            onTap: (_) {},
            onActivate: (_) {},
            onToggleFavourite: (item) => hearted = item,
          ),
        ),
      );

      // One heart, for the file; a folder cannot be favourited.

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();
      expect(hearted?.name, 'beach.jpg');
    });
  });

  group('MediaToolbar', () {
    Widget toolbar({
      required LibrarySection section,
      int selectionCount = 0,
      int fileCount = 0,
      bool allFavourite = false,
      MediaActions? actions,
    }) => _wrap(
      MediaToolbar(
        section: section,
        selectionCount: selectionCount,
        fileCount: fileCount,
        allFavourite: allFavourite,
        sortOption: MediaSortOption.nameAscending,
        actions: actions ?? _actions(),
      ),
    );

    testWidgets('disables the selection actions when nothing is selected', (
      tester,
    ) async {
      await tester.pumpWidget(toolbar(section: LibrarySection.library));

      for (final icon in [
        Icons.favorite_border,
        Icons.info_outline,
        Icons.visibility_outlined,
        Icons.share_outlined,
        Icons.delete_outline,
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
        toolbar(
          section: LibrarySection.library,
          selectionCount: 2,
          fileCount: 2,
          actions: _actions(onDelete: () => deleted = true),
        ),
      );

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      expect(deleted, isTrue);
    });

    testWidgets('Get Info acts on a selected file', (tester) async {
      var asked = false;

      await tester.pumpWidget(
        toolbar(
          section: LibrarySection.library,
          selectionCount: 1,
          fileCount: 1,
          actions: _actions(onGetInfo: () => asked = true),
        ),
      );

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pump();
      expect(asked, isTrue);
    });

    testWidgets('the heart offers to remove when everything is a favourite', (
      tester,
    ) async {
      var toggled = false;

      await tester.pumpWidget(
        toolbar(
          section: LibrarySection.library,
          selectionCount: 1,
          fileCount: 1,
          allFavourite: true,
          actions: _actions(onToggleFavourite: () => toggled = true),
        ),
      );

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsNothing);

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pump();
      expect(toggled, isTrue);
    });

    testWidgets('a folder alone has nothing to preview or describe', (
      tester,
    ) async {
      await tester.pumpWidget(
        toolbar(section: LibrarySection.library, selectionCount: 1),
      );

      for (final icon in [
        Icons.favorite_border,
        Icons.info_outline,
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

    testWidgets('offers Add and Organise in the Library only', (tester) async {
      await tester.pumpWidget(
        toolbar(
          section: LibrarySection.library,
          selectionCount: 1,
          fileCount: 1,
        ),
      );
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);

      await tester.pumpWidget(
        toolbar(
          section: LibrarySection.favourites,
          selectionCount: 1,
          fileCount: 1,
        ),
      );
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
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
            selected: 4,
            onPage: (page) => requested = page,
          ),
        ),
      );

      expect(find.text('20 of 60 shown  ·  4 selected'), findsOneWidget);
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
