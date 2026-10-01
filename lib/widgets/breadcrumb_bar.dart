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
/// than two. The root is shown as "Library" because its real name,
/// `photopod/data`, is an implementation detail the user did not choose.

class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({
    super.key,
    required this.segments,
    required this.onNavigate,
  });

  /// The folder names between the root and the current folder, outermost
  /// first. Empty when the user is at the root.

  final List<String> segments;

  /// Called with the number of segments to keep, so 0 means the root.

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium;

    // Laid out exactly as the other sections' titles are — the same padding,
    // icon and type — so that the name sits in the same place on every page.
    // A long path scrolls sideways rather than pushing the name off the left.

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _crumb(
                    child: Text('Library', style: theme.textTheme.titleSmall),
                    onTap: segments.isEmpty ? null : () => onNavigate(0),
                    first: true,
                  ),
                  for (var i = 0; i < segments.length; i++) ...[
                    Text(' / ', style: style),
                    _crumb(
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
      ),
    );
  }

  // The first step carries no padding of its own on the left, so "Library"
  // lines up with the names on the other pages.

  Widget _crumb({
    required Widget child,
    required VoidCallback? onTap,
    bool first = false,
  }) => InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.fromLTRB(first ? 0 : 4, 8, 4, 8),
      child: child,
    ),
  );
}
