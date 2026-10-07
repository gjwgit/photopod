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
import 'package:markdown_tooltip/markdown_tooltip.dart';

import 'package:photopod/models/library_section.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/view_prefs.dart';
import 'package:photopod/widgets/album_list.dart';
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
  ValueChanged<String>? onAddToAlbum,
  VoidCallback? onCreateAlbum,
  VoidCallback? onDuplicate,
}) => MediaActions(
  onAddFiles: () {},
  onDelete: onDelete ?? () {},
  onDuplicate: onDuplicate ?? () {},
  onRename: () {},
  onShare: () {},
  onView: () {},
  onPreview: () {},
  onGetInfo: onGetInfo ?? () {},
  onToggleFavourite: onToggleFavourite ?? () {},
  onAddToAlbum: onAddToAlbum ?? (_) {},
  onCreateAlbum: onCreateAlbum ?? () {},
  onRemoveFromAlbum: () {},
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

    testWidgets('marks what is shared with the user beside the heart', (
      tester,
    ) async {
      const shared = MediaItem(
        name: 'beach.jpg',
        rawName: 'beach.jpg.enc.ttl',
        path: 'https://pod.example/alice/photopod/data/beach.jpg.enc.ttl',
        url: 'https://pod.example/alice/photopod/data/beach.jpg.enc.ttl',
        isFolder: false,
        isEncrypted: true,
        sharedBy: 'https://pod.example/alice/profile/card#me',
      );

      await tester.pumpWidget(_wrap(_grid([_item('own.jpg'), shared])));

      expect(find.byIcon(Icons.people), findsOneWidget);
      expect(find.bySemanticsLabel('Shared with you by alice'), findsOneWidget);
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
      List<String> albumNames = const [],
      MediaActions? actions,
      bool hasShared = false,
    }) => _wrap(
      MediaToolbar(
        section: section,
        selectionCount: selectionCount,
        fileCount: fileCount,
        allFavourite: allFavourite,
        sortOption: MediaSortOption.nameAscending,
        actions: actions ?? _actions(),
        albumNames: albumNames,
        hasShared: hasShared,
      ),
    );

    testWidgets('will not change what someone else shared', (tester) async {
      await tester.pumpWidget(
        toolbar(
          section: LibrarySection.library,
          selectionCount: 1,
          fileCount: 1,
          hasShared: true,
        ),
      );

      IconButton button(IconData icon) => tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)),
      );

      for (final icon in [
        Icons.content_copy,
        Icons.drive_file_rename_outline,
        Icons.delete_outline,
        Icons.share_outlined,
      ]) {
        expect(button(icon).onPressed, isNull, reason: '$icon');
      }

      // Looking at it, giving it a heart and putting it in an album are all
      // still the user's to do.

      expect(button(Icons.visibility_outlined).onPressed, isNotNull);
      expect(button(Icons.favorite_border).onPressed, isNotNull);
      expect(button(Icons.drive_file_move_outline).onPressed, isNotNull);
    });

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

    testWidgets('offers Add in the Library only', (tester) async {
      await tester.pumpWidget(toolbar(section: LibrarySection.library));
      expect(find.byIcon(Icons.add), findsOneWidget);

      await tester.pumpWidget(toolbar(section: LibrarySection.favourites));
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('puts Duplicate and Rename in the row, with no menu', (
      tester,
    ) async {
      var duplicated = false;
      var renamed = false;

      await tester.pumpWidget(
        toolbar(
          section: LibrarySection.favourites,
          selectionCount: 1,
          fileCount: 1,
          actions: MediaActions(
            onAddFiles: () {},
            onDelete: () {},
            onDuplicate: () => duplicated = true,
            onRename: () => renamed = true,
            onShare: () {},
            onView: () {},
            onPreview: () {},
            onGetInfo: () {},
            onToggleFavourite: () {},
            onAddToAlbum: (_) {},
            onCreateAlbum: () {},
            onRemoveFromAlbum: () {},
            onRefresh: () {},
            onSort: (_) {},
          ),
        ),
      );

      expect(find.byIcon(Icons.more_horiz), findsNothing);

      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.tap(find.byIcon(Icons.drive_file_rename_outline));
      await tester.pump();
      expect(duplicated, isTrue);
      expect(renamed, isTrue);
    });

    testWidgets('draws every icon at the same size', (tester) async {
      await tester.pumpWidget(
        toolbar(
          section: LibrarySection.albums,
          selectionCount: 1,
          fileCount: 1,
        ),
      );

      final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
      expect(buttons, isNotEmpty);
      for (final button in buttons) {
        expect(button.iconSize, toolbarIconSize);
      }

      final sizes = tester
          .widgetList(find.byType(IconButton))
          .map((widget) => tester.getSize(find.byWidget(widget)))
          .toSet();
      expect(sizes, hasLength(1));
    });

    testWidgets('Add to album lists Favourites, every album and a new one', (
      tester,
    ) async {
      String? chosen;
      var created = false;

      await tester.pumpWidget(
        toolbar(
          section: LibrarySection.library,
          selectionCount: 1,
          fileCount: 1,
          albumNames: const ['Holiday', 'Wedding'],
          actions: _actions(
            onAddToAlbum: (album) => chosen = album,
            onCreateAlbum: () => created = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.drive_file_move_outline));
      await tester.pumpAndSettle();

      expect(find.text('Favourites'), findsOneWidget);
      expect(find.text('Holiday'), findsOneWidget);
      expect(find.text('Wedding'), findsOneWidget);
      expect(find.text('Create new album...'), findsOneWidget);

      await tester.tap(find.text('Wedding'));
      await tester.pumpAndSettle();
      expect(chosen, 'Wedding');

      await tester.tap(find.byIcon(Icons.drive_file_move_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create new album...'));
      await tester.pumpAndSettle();
      expect(created, isTrue);
    });

    testWidgets('Add to album waits for a selected file', (tester) async {
      await tester.pumpWidget(toolbar(section: LibrarySection.library));

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.drive_file_move_outline),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('keeps to the agreed order, Create new album first', (
      tester,
    ) async {
      await tester.pumpWidget(
        toolbar(
          section: LibrarySection.albums,
          selectionCount: 1,
          fileCount: 1,
        ),
      );

      final labels = tester
          .widgetList<Semantics>(
            find.descendant(
              of: find.byType(MediaToolbar),
              matching: find.byType(Semantics),
            ),
          )
          .map((each) => each.properties.label)
          .whereType<String>()
          .where((label) => label.isNotEmpty)
          .toList();

      expect(labels, [
        'Create new album',
        'Add to Favourites',
        'Add to album',
        'Duplicate',
        'Preview',
        'Rename',
        'Delete',
        'Remove from album',
        'Share',
        'Get Info',
        'Sort',
        'View',
        'Refresh',
      ]);
    });

    testWidgets('every button carries a Markdown tooltip', (tester) async {
      await tester.pumpWidget(
        toolbar(
          section: LibrarySection.albums,
          selectionCount: 1,
          fileCount: 1,
        ),
      );

      for (final element in find.byType(IconButton).evaluate()) {
        expect(
          find.ancestor(
            of: find.byWidget(element.widget),
            matching: find.byType(MarkdownTooltip),
          ),
          findsWidgets,
        );
      }
    });

    testWidgets('offers Create new album in the Albums section only', (
      tester,
    ) async {
      await tester.pumpWidget(toolbar(section: LibrarySection.library));
      expect(find.bySemanticsLabel('Create new album'), findsNothing);

      await tester.pumpWidget(toolbar(section: LibrarySection.albums));
      expect(find.bySemanticsLabel('Create new album'), findsOneWidget);
    });

    testWidgets('offers Remove from album in the Albums section only', (
      tester,
    ) async {
      await tester.pumpWidget(toolbar(section: LibrarySection.library));
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);

      await tester.pumpWidget(toolbar(section: LibrarySection.albums));
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    });
  });

  group('AlbumList', () {
    Widget albumList({
      required List<AlbumEntry> albums,
      void Function(String)? onShare,
      void Function(String)? onRename,
      void Function(String)? onDelete,
    }) => _wrap(
      AlbumList(
        albums: albums,
        tileExtent: 100,
        isSelected: (_, _) => false,
        isFavourite: (_) => false,
        onTap: (_, _) {},
        onActivate: (_, _) {},
        onToggleFavourite: (_) {},
        onShare: onShare ?? (_) {},
        onRemoveFromAlbum: (_, _) {},
        onRename: onRename ?? (_) {},
        onDelete: onDelete ?? (_) {},
      ),
    );

    testWidgets('marks an album shared with the user, with no buttons', (
      tester,
    ) async {
      await tester.pumpWidget(
        albumList(
          albums: const [
            AlbumEntry(
              id: 'https://pod.example/alice/photopod/data/albums/Holiday.json',
              name: 'Holiday',
              items: [],
              sharedBy: 'https://pod.example/alice/profile/card#me',
            ),
          ],
        ),
      );

      expect(find.byIcon(Icons.people), findsOneWidget);
      expect(find.text('0 items · shared by alice'), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('marks an album the user has shared', (tester) async {
      await tester.pumpWidget(
        albumList(
          albums: const [
            AlbumEntry(name: 'Holiday', items: [], isSharedOut: true),
          ],
        ),
      );

      expect(find.byIcon(Icons.people), findsOneWidget);
      expect(find.text('0 items · shared'), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    });

    testWidgets('gives Favourites no edit or delete button', (tester) async {
      await tester.pumpWidget(
        albumList(
          albums: [
            const AlbumEntry(name: 'Favourites', items: [], isSystem: true),
            AlbumEntry(name: 'Holiday', items: [_item('beach.jpg')]),
          ],
        ),
      );

      expect(find.text('Favourites'), findsOneWidget);
      expect(find.text('Holiday'), findsOneWidget);
      expect(find.text('1 item'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('offers every album, Favourites included, a share button', (
      tester,
    ) async {
      final shared = <String>[];

      await tester.pumpWidget(
        albumList(
          albums: const [
            AlbumEntry(name: 'Favourites', items: [], isSystem: true),
            AlbumEntry(name: 'Holiday', items: []),
          ],
          onShare: shared.add,
        ),
      );

      final buttons = find.byIcon(Icons.share_outlined);
      expect(buttons, findsNWidgets(2));
      await tester.tap(buttons.first);
      await tester.tap(buttons.last);
      await tester.pump();
      expect(shared, ['Favourites', 'Holiday']);
    });

    testWidgets('reports rename and delete for the right album', (
      tester,
    ) async {
      String? renamed;
      String? deleted;

      await tester.pumpWidget(
        albumList(
          albums: const [AlbumEntry(name: 'Holiday', items: [])],
          onRename: (album) => renamed = album,
          onDelete: (album) => deleted = album,
        ),
      );

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      expect(renamed, 'Holiday');
      expect(deleted, 'Holiday');
    });

    testWidgets('opens into a sideways row of tiles', (tester) async {
      await tester.pumpWidget(
        albumList(
          albums: [
            AlbumEntry(
              name: 'Holiday',
              items: [_item('a.mp4'), _item('b.mp4'), _item('c.mp4')],
            ),
          ],
        ),
      );

      expect(find.byType(MediaTile), findsNothing);

      await tester.tap(find.text('Holiday'));
      await tester.pumpAndSettle();

      expect(find.byType(MediaTile), findsNWidgets(3));
      final row = tester.widget<ListView>(
        find.descendant(
          of: find.byType(ExpansionTile),
          matching: find.byType(ListView),
        ),
      );
      expect(row.scrollDirection, Axis.horizontal);
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
          ),
        ),
      );

      expect(find.text('holiday'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);

      await tester.tap(find.text('holiday'));
      await tester.pump();
      expect(kept, 1);
    });

    testWidgets('names the root Library, with no home or up button', (
      tester,
    ) async {
      int? kept;

      await tester.pumpWidget(
        _wrap(
          BreadcrumbBar(
            segments: const ['holiday'],
            onNavigate: (keep) => kept = keep,
          ),
        ),
      );

      expect(find.byIcon(Icons.home_outlined), findsNothing);
      expect(find.byIcon(Icons.arrow_upward), findsNothing);

      await tester.tap(find.text('Library'));
      await tester.pump();
      expect(kept, 0);
    });
  });
}
