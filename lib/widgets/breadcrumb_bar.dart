/// Show and navigate the current folder path.
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

/// The trail of folders from the album root down to where the user is now.
///
/// Each step is a button, so getting back up two levels is one tap rather
/// than two. The root is shown as a home icon because its real name,
/// `photopod/data`, is an implementation detail the user did not choose.

class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({
    super.key,
    required this.segments,
    required this.onNavigate,
    required this.onUp,
  });

  /// The folder names between the root and the current folder, outermost
  /// first. Empty when the user is at the root.

  final List<String> segments;

  /// Called with the number of segments to keep, so 0 means the root.

  final ValueChanged<int> onNavigate;

  /// Called to go up one level, or null at the root.

  final VoidCallback? onUp;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_upward),
          tooltip: 'Up one folder',
          onPressed: onUp,
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              children: [
                _crumb(
                  context,
                  child: const Icon(Icons.home_outlined, size: 20),
                  onTap: segments.isEmpty ? null : () => onNavigate(0),
                ),
                for (var i = 0; i < segments.length; i++) ...[
                  Text(' / ', style: style),
                  _crumb(
                    context,
                    child: Text(segments[i], style: style),
                    onTap: i == segments.length - 1
                        ? null
                        : () => onNavigate(i + 1),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _crumb(
    BuildContext context, {
    required Widget child,
    required VoidCallback? onTap,
  }) => InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: child,
    ),
  );
}
