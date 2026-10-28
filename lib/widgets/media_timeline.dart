/// The Library laid out as a timeline, one day under each heading.
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

import 'package:photopod/models/media_item.dart';
import 'package:photopod/widgets/date_scrubber.dart';
import 'package:photopod/widgets/media_grid.dart';
import 'package:photopod/widgets/media_thumbnail.dart';
import 'package:photopod/widgets/timeline_layout.dart';

export 'package:photopod/widgets/timeline_layout.dart';

/// The Library in the tiled view: memories along the top, then any folders,
/// then every photo and video under the day it is dated, the latest day
/// first, with a scroll bar down the right that moves through the years.

class MediaTimeline extends StatefulWidget {
  const MediaTimeline({
    super.key,
    required this.groups,
    required this.memories,
    required this.isSelected,
    required this.isFavourite,
    required this.onTap,
    required this.onActivate,
    required this.onToggleFavourite,
    required this.onOpenMemory,
    this.tileExtent = 140,
  });

  /// The folders, if any, followed by the days.

  final List<TimelineGroup> groups;

  /// What dates from this day in earlier years.

  final List<TimelineMemory> memories;

  /// Whether an item is part of the current selection.

  final bool Function(MediaItem) isSelected;

  /// Whether an item carries a heart.

  final bool Function(MediaItem) isFavourite;

  /// Called on a single tap, which changes the selection.

  final void Function(MediaItem) onTap;

  /// Called on a double tap, which opens a folder or previews a file.

  final void Function(MediaItem) onActivate;

  /// Called when the heart on a tile is tapped.

  final void Function(MediaItem) onToggleFavourite;

  /// Called when a memory is opened.

  final void Function(TimelineMemory) onOpenMemory;

  /// The widest a tile may be, from the user's View preferences.

  final double tileExtent;

  @override
  State<MediaTimeline> createState() => _MediaTimelineState();
}

class _MediaTimelineState extends State<MediaTimeline> {
  final _controller = ScrollController();
  final _labelWidths = <String, double>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  TextStyle? _labelStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);

  double _measure(String label, TextStyle? style) =>
      _labelWidths.putIfAbsent(label, () {
        final painter = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final width = painter.width + 4;
        painter.dispose();
        return width;
      });

  @override
  Widget build(BuildContext context) {
    final style = _labelStyle(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = TimelineLayout.build(
          groups: widget.groups,
          width: constraints.maxWidth - DateScrubber.width,
          extent: widget.tileExtent,
          measure: (label) => _measure(label, style),
          hasMemories: widget.memories.isNotEmpty,
        );

        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: DateScrubber.width),
              child: ScrollConfiguration(
                // The date scroll bar stands in for the usual one.
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: ListView.builder(
                  controller: _controller,
                  itemCount: layout.lines.length,
                  itemExtentBuilder: (index, _) => index < layout.lines.length
                      ? layout.lines[index].height
                      : null,
                  itemBuilder: (context, index) {
                    final line = layout.lines[index];
                    return line.isMemories
                        ? _buildMemories(context)
                        : _buildLine(context, line, layout.tile, style);
                  },
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: DateScrubber.width,
              child: DateScrubber(
                controller: _controller,
                months: layout.months,
                height: layout.height,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLine(
    BuildContext context,
    TimelineLine line,
    double tile,
    TextStyle? style,
  ) => Stack(
    children: [
      for (final placed in line.placements) ...[
        if (placed.showsLabel)
          Positioned(
            left: TimelineLayout.padding + placed.left,
            top: 0,
            width: placed.width,
            height: TimelineLayout.labelHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                placed.group.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
        Positioned(
          left: TimelineLayout.padding + placed.left,
          top: placed.showsLabel ? TimelineLayout.labelHeight : 0,
          height: tile,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, item) in placed.items.indexed) ...[
                if (index > 0) const SizedBox(width: TimelineLayout.spacing),
                SizedBox(
                  width: tile,
                  height: tile,
                  child: MediaTile(
                    key: ValueKey(item.id),
                    item: item,
                    selected: widget.isSelected(item),
                    favourite: widget.isFavourite(item),
                    onTap: () => widget.onTap(item),
                    onActivate: () => widget.onActivate(item),
                    onToggleFavourite: () => widget.onToggleFavourite(item),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ],
  );

  Widget _buildMemories(BuildContext context) => ListView.separated(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(
      TimelineLayout.padding,
      TimelineLayout.padding,
      TimelineLayout.padding,
      8,
    ),
    itemCount: widget.memories.length,
    separatorBuilder: (context, index) => const SizedBox(width: 12),
    itemBuilder: (context, index) => _MemoryCard(
      memory: widget.memories[index],
      onOpen: () => widget.onOpenMemory(widget.memories[index]),
    ),
  );
}

/// One memory: its newest photo, with how long ago across the bottom.

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.memory, required this.onOpen});

  final TimelineMemory memory;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final count = memory.items.length;

    return Tooltip(
      message: '${memory.label}: $count ${count == 1 ? 'item' : 'items'}',
      child: Semantics(
        button: true,
        label: memory.label,
        child: GestureDetector(
          onTap: onOpen,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 120,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: MediaThumbnail(item: memory.items.first),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black54],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Text(
                        memory.label,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
