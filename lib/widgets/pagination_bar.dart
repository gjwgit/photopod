/// Step through a large album a page at a time.
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

/// The page controls shown beneath the grid or list.
///
/// An album can easily hold thousands of photos, and every thumbnail is a
/// separate request to the Solid server, so PhotoPod shows a page at a time
/// and fetches only what is on it.

class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.pageCount,
    required this.total,
    required this.shown,
    required this.selected,
    required this.onPage,
  });

  /// The current page, counting from zero.

  final int page;

  /// How many pages there are altogether, at least one.

  final int pageCount;

  /// How many items are in the folder.

  final int total;

  /// How many items are on this page.

  final int shown;

  /// How many items are selected.

  final int selected;

  /// Called with the page to move to.

  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final summary = selected > 0
        ? '$shown of $total shown  ·  $selected selected'
        : '$shown of $total shown';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(summary, style: style)),
          if (pageCount > 1) ...[
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous page',
              onPressed: page > 0 ? () => onPage(page - 1) : null,
            ),
            Text('Page ${page + 1} of $pageCount', style: style),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next page',
              onPressed: page < pageCount - 1 ? () => onPage(page + 1) : null,
            ),
          ],
        ],
      ),
    );
  }
}
