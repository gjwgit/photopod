/// Tests for the timeline: days, memories and how rows are packed.
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

import 'package:photopod/models/media_item.dart';
import 'package:photopod/widgets/media_timeline.dart';

MediaItem _file(String name, DateTime? modified) => MediaItem(
  name: name,
  rawName: name,
  path: 'photopod/data/$name',
  url: 'https://pod.example/photopod/data/$name',
  isFolder: false,
  modified: modified,
);

List<MediaItem> _day(DateTime day, int count) => [
  for (var i = 0; i < count; i++)
    _file('${day.toIso8601String()}-$i.jpg', day.add(Duration(minutes: i))),
];

void main() {
  final now = DateTime(2026, 10, 28, 9);

  group('groupByDay', () {
    test('puts the latest day first and the latest item first in a day', () {
      final groups = groupByDay([
        _file('old.jpg', DateTime(2025, 4, 5, 10)),
        _file('morning.jpg', DateTime(2026, 4, 4, 8)),
        _file('evening.jpg', DateTime(2026, 4, 4, 20)),
      ], now: now);

      expect(groups.map((g) => g.label), ['Sat, 4 April', 'Sat, 5 April 2025']);
      expect(groups.first.items.map((i) => i.name), [
        'evening.jpg',
        'morning.jpg',
      ]);
    });

    test('files an item under the day it was taken, not uploaded', () {
      final item = MediaItem(
        name: 'taken.jpg',
        rawName: 'taken.jpg',
        path: 'photopod/data/taken.jpg',
        url: 'https://pod.example/photopod/data/taken.jpg',
        isFolder: false,
        modified: DateTime(2026, 10, 27, 12),
        taken: DateTime(2019, 4, 6, 15),
      );
      final groups = groupByDay([item], now: now);

      expect(groups.single.label, 'Sat, 6 April 2019');
    });

    test('moves an item to its day once its date is filled in', () {
      final item = _file('old.jpg', DateTime(2026, 10, 27, 12));
      final dated = item.withTaken(DateTime(2018, 4, 7, 15));

      expect(identical(item.withTaken(null), item), isTrue);
      expect(dated.url, item.url);
      expect(groupByDay([dated], now: now).single.label, 'Sat, 7 April 2018');
    });

    test('keeps undated items, in a group of their own at the end', () {
      final groups = groupByDay([
        _file('undated.jpg', null),
        _file('dated.jpg', DateTime(2026, 1, 1, 12)),
      ], now: now);

      expect(groups.last.label, 'Date unknown');
      expect(groups.last.day, isNull);
      expect(groups.last.items.single.name, 'undated.jpg');
    });
  });

  group('memoriesOf', () {
    test('sorts photos into bands of 1, 2, 5 and 10 years ago', () {
      final memories = memoriesOf([
        _file('recent.jpg', DateTime(2026, 1, 1, 12)),
        _file('one.jpg', DateTime(2025, 10, 28, 12)),
        _file('one-and-a-half.jpg', DateTime(2025, 3, 1, 12)),
        _file('three.jpg', DateTime(2023, 6, 1, 12)),
        _file('twelve.jpg', DateTime(2014, 6, 1, 12)),
      ], now: now);

      expect(memories.map((m) => m.label), [
        '1 year ago',
        '2 years ago',
        '10 years ago',
      ]);
      expect(memories.first.items.map((i) => i.name), [
        'one.jpg',
        'one-and-a-half.jpg',
      ]);
    });

    test('puts what is nearest to today\'s date in its year first', () {
      final memories = memoriesOf([
        _file('june.jpg', DateTime(2022, 6, 1, 12)),
        _file('november.jpg', DateTime(2021, 11, 2, 12)),
      ], now: now);

      expect(memories.single.label, '2 years ago');
      expect(memories.single.items.first.name, 'november.jpg');
    });

    test('has nothing to show for an album under a year old', () {
      expect(memoriesOf([_file('new.jpg', now)], now: now), isEmpty);
    });
  });

  group('TimelineLayout', () {
    // 4 columns of 100 across 412 usable pixels plus the padding.
    const width = 412 + 2 * TimelineLayout.padding;

    TimelineLayout layoutOf(List<TimelineGroup> groups) => TimelineLayout.build(
      groups: groups,
      width: width,
      extent: 100,
      measure: (_) => 50,
    );

    test('puts small days side by side while they fit', () {
      final layout = layoutOf(
        groupByDay([
          ..._day(DateTime(2026, 10, 3), 1),
          ..._day(DateTime(2026, 10, 2), 2),
          ..._day(DateTime(2026, 10, 1), 2),
        ], now: now),
      );

      expect(layout.columns, 4);
      expect(layout.lines.map((l) => l.placements.length), [2, 1]);
    });

    test('gives a long day a row of its own for each row of tiles', () {
      final layout = layoutOf(
        groupByDay([
          ..._day(DateTime(2026, 10, 2), 1),
          ..._day(DateTime(2026, 10, 1), 9),
        ], now: now),
      );

      expect(layout.lines.map((l) => l.placements.single.count), [1, 4, 4, 1]);
      expect(layout.lines.map((l) => l.placements.single.showsLabel), [
        true,
        true,
        false,
        false,
      ]);
      expect(layout.height, layout.lines.fold(0.0, (sum, l) => sum + l.height));
    });

    test('marks each month where it first appears', () {
      final layout = layoutOf(
        groupByDay([
          ..._day(DateTime(2026, 10, 1), 4),
          ..._day(DateTime(2026, 9, 30), 4),
          ..._day(DateTime(2026, 9, 1), 1),
        ], now: now),
      );

      expect(layout.months.map((m) => m.month), [
        DateTime(2026, 10),
        DateTime(2026, 9),
      ]);
      expect(layout.months.last.offset, layout.lines[1].offset);
    });
  });

  testWidgets('MediaTimeline shows memories, days and years down the side', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final files = [
      for (var month = 1; month <= 12; month++)
        ..._day(DateTime(2026, month, 5), 6),
      for (var month = 1; month <= 12; month++)
        ..._day(DateTime(2024, month, 5), 6),
      for (var month = 1; month <= 12; month++)
        ..._day(DateTime(2025, month, 5), 6),
      _file('memory.jpg', DateTime(2025, 10, 28, 12)),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaTimeline(
            groups: groupByDay(files),
            memories: memoriesOf(files, now: now),
            isSelected: (_) => false,
            isFavourite: (_) => false,
            onTap: (_) {},
            onActivate: (_) {},
            onToggleFavourite: (_) {},
            onOpenMemory: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('1 year ago'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
