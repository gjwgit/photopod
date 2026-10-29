/// The days of the timeline, its memories, and how they are packed into rows.
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

import 'dart:math' as math;

import 'package:photopod/models/media_item.dart';
import 'package:photopod/utils/formatting.dart';

/// The photos and videos under one heading: a single day, the folders, or
/// everything the server gave no date for.

class TimelineGroup {
  const TimelineGroup({required this.label, required this.items, this.day});

  /// The heading, such as `Sat, 5 April`.

  final String label;

  /// Local midnight of the day the group holds, or null for a group that is
  /// not a day. A group without a day always has a row to itself.

  final DateTime? day;

  /// The items under the heading, in the order they are shown.

  final List<MediaItem> items;
}

/// Where each memory along the top starts, in years back. Each one runs
/// until the next begins, and the last has no end.

const List<int> memoryYears = [1, 2, 5, 10];

/// The photos and videos from some years ago: from [years] back up to the
/// next of [memoryYears].

class TimelineMemory {
  const TimelineMemory({required this.years, required this.items});

  /// How many years ago the memory starts.

  final int years;

  /// What dates from then, the items nearest to today's date in their own
  /// year first.

  final List<MediaItem> items;

  /// The caption on the card, such as `5 years ago`.

  String get label => years == 1 ? '1 year ago' : '$years years ago';
}

/// Group [files] by the local day of their [MediaItem.date], which is when
/// each was taken where that is known, newest day first and newest item
/// first within each day. Anything without a date goes into one group at the
/// end, so that nothing silently disappears from the Library.

List<TimelineGroup> groupByDay(Iterable<MediaItem> files, {DateTime? now}) {
  final byDay = <DateTime, List<MediaItem>>{};
  final undated = <MediaItem>[];

  for (final item in files) {
    final when = item.date?.toLocal();
    if (when == null) {
      undated.add(item);
    } else {
      byDay
          .putIfAbsent(DateTime(when.year, when.month, when.day), () => [])
          .add(item);
    }
  }

  int newestFirst(MediaItem a, MediaItem b) {
    final result = b.date!.compareTo(a.date!);
    return result != 0
        ? result
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  undated.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return [
    for (final day in days)
      TimelineGroup(
        label: formatDayHeading(day, now: now),
        day: day,
        items: byDay[day]!..sort(newestFirst),
      ),
    if (undated.isNotEmpty)
      TimelineGroup(label: 'Date unknown', items: undated),
  ];
}

/// Sort [files] into the memories: `1 year ago` holds what is at least one
/// but less than two years old, `2 years ago` from two to five, `5 years ago`
/// from five to ten and `10 years ago` anything older. A memory with nothing
/// in it is left out.
///
/// Within each, what was taken nearest to today's date in its own year comes
/// first, so the card's picture is the one most like "this time that year".

List<TimelineMemory> memoriesOf(Iterable<MediaItem> files, {DateTime? now}) {
  final today = now ?? DateTime.now();
  DateTime yearsBack(int years) =>
      DateTime(today.year - years, today.month, today.day + 1);

  // How far, in days around the calendar, [when] is from today's date in
  // its own year.

  int fromToday(DateTime when) {
    final days = DateTime.utc(
      when.year,
      when.month,
      when.day,
    ).difference(DateTime.utc(when.year, today.month, today.day)).inDays.abs();
    return math.min(days, 365 - days);
  }

  final memories = <TimelineMemory>[];
  for (final (index, years) in memoryYears.indexed) {
    final newest = yearsBack(years);
    final oldest = index + 1 < memoryYears.length
        ? yearsBack(memoryYears[index + 1])
        : null;

    final items =
        files.where((item) {
          final when = item.date?.toLocal();
          return when != null &&
              when.isBefore(newest) &&
              (oldest == null || !when.isBefore(oldest));
        }).toList()..sort((a, b) {
          final result = fromToday(
            a.date!.toLocal(),
          ).compareTo(fromToday(b.date!.toLocal()));
          return result != 0 ? result : b.date!.compareTo(a.date!);
        });
    if (items.isNotEmpty) {
      memories.add(TimelineMemory(years: years, items: items));
    }
  }
  return memories;
}

/// Where the groups sit once they are packed into rows of a given width.
///
/// A day small enough to fit in what is left of a row sits beside the day
/// before it, under its own heading, as Immich does; a day with more items
/// than a row holds starts a fresh row and takes as many as it needs. Every
/// row has a fixed height, which is what lets the date scroll bar jump
/// straight to any day without building the rows in between.

class TimelineLayout {
  TimelineLayout._(this.lines, this.tile, this.columns);

  /// Space around the edge of the timeline.

  static const double padding = 12;

  /// Space between two tiles.

  static const double spacing = 4;

  /// Space between two days sharing a row.

  static const double groupGap = 20;

  /// Height given to the headings above a row.

  static const double labelHeight = 40;

  /// Height of the row of memories.

  static const double memoriesHeight = 180;

  /// Lay [groups] out across [width], with tiles no wider than [extent],
  /// after a row of memories when [hasMemories]. [measure] gives the width a
  /// heading needs, so that a day of one small tile still has room for its
  /// date.

  factory TimelineLayout.build({
    required List<TimelineGroup> groups,
    required double width,
    required double extent,
    required double Function(String label) measure,
    bool hasMemories = false,
  }) {
    final usable = math.max(1.0, width - 2 * padding);
    final columns = math.max(
      1,
      ((usable + spacing) / (extent + spacing)).floor(),
    );
    final tile = (usable - (columns - 1) * spacing) / columns;
    final lines = <TimelineLine>[];
    var offset = 0.0;

    void add(TimelineLine line) {
      lines.add(line.._offset = offset);
      offset += line.height;
    }

    if (hasMemories) add(TimelineLine._memories());

    var row = <TimelinePlacement>[];
    var x = 0.0;

    void flush() {
      if (row.isEmpty) return;
      add(TimelineLine._(row, labelHeight + tile + spacing));
      row = [];
      x = 0;
    }

    for (final group in groups) {
      final count = group.items.length;
      final tiles = count * tile + (count - 1) * spacing;

      if (count <= columns && group.day != null) {
        final box = math.min(usable, math.max(tiles, measure(group.label)));
        if (row.isNotEmpty && x + groupGap + box > usable + 0.5) flush();
        final left = row.isEmpty ? 0.0 : x + groupGap;
        row.add(TimelinePlacement._(group, 0, count, left, box, true));
        x = left + box;
        continue;
      }

      flush();
      for (var start = 0; start < count; start += columns) {
        final first = start == 0;
        add(
          TimelineLine._([
            TimelinePlacement._(
              group,
              start,
              math.min(columns, count - start),
              0,
              usable,
              first,
            ),
          ], (first ? labelHeight : 0) + tile + spacing),
        );
      }
    }
    flush();

    return TimelineLayout._(lines, tile, columns);
  }

  /// The rows, top to bottom.

  final List<TimelineLine> lines;

  /// The width and height of one tile.

  final double tile;

  /// How many tiles fit across.

  final int columns;

  /// The height of everything, top to bottom.

  double get height =>
      lines.isEmpty ? 0 : lines.last.offset + lines.last.height;

  /// Where each month first appears, top to bottom, which is what the date
  /// scroll bar marks.

  List<({DateTime month, double offset})> get months {
    final marks = <({DateTime month, double offset})>[];
    for (final line in lines) {
      for (final placed in line.placements) {
        final day = placed.group.day;
        if (day == null) continue;
        final month = DateTime(day.year, day.month);
        if (marks.isEmpty || marks.last.month != month) {
          marks.add((month: month, offset: line.offset));
        }
      }
    }
    return marks;
  }
}

/// One row of the timeline.

class TimelineLine {
  TimelineLine._(this.placements, this.height) : isMemories = false;

  TimelineLine._memories()
    : placements = const [],
      height = TimelineLayout.memoriesHeight,
      isMemories = true;

  /// The groups, or the part of one group, in this row, left to right.

  final List<TimelinePlacement> placements;

  /// How tall the row is, headings included.

  final double height;

  /// Whether this is the row of memories rather than a row of tiles.

  final bool isMemories;

  double _offset = 0;

  /// How far down the timeline the row starts.

  double get offset => _offset;
}

/// Where one group, or one row's worth of a long group, sits within a row.

class TimelinePlacement {
  TimelinePlacement._(
    this.group,
    this.start,
    this.count,
    this.left,
    this.width,
    this.showsLabel,
  );

  /// The group the tiles come from.

  final TimelineGroup group;

  /// The index of the first of its items in this row.

  final int start;

  /// How many of its items are in this row.

  final int count;

  /// Distance from the left of the row.

  final double left;

  /// The width the group takes up, heading included.

  final double width;

  /// Whether the heading is drawn above it, which is so for the first row of
  /// a group only.

  final bool showsLabel;

  /// The items in this row.

  Iterable<MediaItem> get items => group.items.skip(start).take(count);
}
