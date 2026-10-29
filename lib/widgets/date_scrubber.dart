/// The scroll bar down the right of the timeline, marked by date.
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

import 'package:photopod/utils/formatting.dart';

/// The scroll bar down the right of the timeline.
///
/// A dot marks each month and a label each year, at the height that month
/// starts at within the timeline. Dragging or tapping anywhere along it jumps
/// there, and while the pointer is over it a bubble names the month it is
/// pointing at.

class DateScrubber extends StatefulWidget {
  const DateScrubber({
    super.key,
    required this.controller,
    required this.months,
    required this.height,
  });

  /// How wide the scroll bar is.

  static const double width = 48;

  /// The timeline's scroll position, which the bar both shows and moves.

  final ScrollController controller;

  /// Where each month first appears down the timeline.

  final List<({DateTime month, double offset})> months;

  /// The height of the whole timeline.

  final double height;

  @override
  State<DateScrubber> createState() => _DateScrubberState();
}

class _DateScrubberState extends State<DateScrubber> {
  /// Where the pointer is along the bar, while it is over it.

  double? _pointer;
  bool _dragging = false;

  void _jump(double y, double track) {
    final controller = widget.controller;
    if (!controller.hasClients) return;
    final target = (y / track * widget.height).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.jumpTo(target);
  }

  /// The month starting at or above [offset] down the timeline.

  DateTime? _monthAt(double offset) {
    DateTime? found;
    for (final mark in widget.months) {
      if (mark.offset > offset) break;
      found = mark.month;
    }
    return found ?? widget.months.firstOrNull?.month;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.months.isEmpty || widget.height <= 0) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall;

    return LayoutBuilder(
      builder: (context, constraints) {
        final track = constraints.maxHeight;
        if (track <= 0 || widget.height <= track) {
          return const SizedBox.shrink();
        }
        double toY(double offset) => offset / widget.height * track;

        // Labels too close to the one above would overprint it, so the
        // later of the two is left out; likewise for the dots.

        final years = <Widget>[];
        final dots = <Widget>[];
        double? lastLabel;
        double? lastDot;
        int? lastYear;
        for (final mark in widget.months) {
          final y = toY(mark.offset);
          if (mark.month.year != lastYear) {
            lastYear = mark.month.year;
            if (lastLabel == null || y - lastLabel >= 18) {
              lastLabel = y;
              years.add(
                Positioned(
                  top: y,
                  right: 4,
                  child: Text(
                    '${mark.month.year}',
                    style: small?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              );
              continue;
            }
          }
          if ((lastDot == null || y - lastDot >= 6) &&
              (lastLabel == null || y - lastLabel >= 14)) {
            lastDot = y;
            dots.add(
              Positioned(
                top: y + 6,
                right: 12,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outline,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }
        }

        final pointer = _pointer;
        final pointed = pointer == null
            ? null
            : _monthAt(pointer / track * widget.height);

        return MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          onHover: (event) => setState(() => _pointer = event.localPosition.dy),
          onExit: (_) {
            if (!_dragging) setState(() => _pointer = null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _jump(details.localPosition.dy, track),
            onVerticalDragStart: (details) {
              setState(() {
                _dragging = true;
                _pointer = details.localPosition.dy;
              });
              _jump(details.localPosition.dy, track);
            },
            onVerticalDragUpdate: (details) {
              final y = details.localPosition.dy.clamp(0.0, track);
              setState(() => _pointer = y);
              _jump(y, track);
            },
            onVerticalDragEnd: (_) => setState(() {
              _dragging = false;
              _pointer = null;
            }),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ...dots,
                ...years,

                // Where the timeline is scrolled to now.
                AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    final offset = widget.controller.hasClients
                        ? widget.controller.offset
                        : 0.0;
                    return Positioned(
                      top: toY(offset).clamp(0.0, track - 3),
                      right: 2,
                      child: Container(
                        width: 28,
                        height: 3,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  },
                ),

                if (pointer != null && pointed != null)
                  Positioned(
                    top: (pointer - 14).clamp(0.0, track - 28),
                    right: DateScrubber.width,
                    child: IgnorePointer(
                      child: Material(
                        elevation: 2,
                        color: scheme.inverseSurface,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          child: Text(
                            formatMonthYear(pointed),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: scheme.onInverseSurface),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
