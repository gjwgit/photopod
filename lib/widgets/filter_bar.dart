/// The bar above the photos that narrows them down to those matching a search.
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
/// Authors: Graham Williams

library;

import 'package:flutter/material.dart';

import 'package:markdown_tooltip/markdown_tooltip.dart';
import 'package:provider/provider.dart';

import 'package:photopod/models/media_filter.dart';

/// How the filter bar is used, shown from its help icon.

const String filterHelp = '''
**Filter** the photos and videos shown. Every term must match.

- `beach` — a word in the name, title, tags or people
- `person:jane` or `person:"Jane Doe"` — someone in the photo
- `tag:sunset` — a tag
- `title:harbour` — a word in the title
- `name:IMG_` — part of the file name
- `date:2026`, `date:2026-10`, `date:2026-10-17`, `date:october`
- `date:2025-12..2026-02` — a range; leave an end open as in `date:2025..`
- `location:yes` or `location:no` — whether it says where it was taken
- `location:-35.28,149.13` — within 10 km of a point, or
  `location:-35.28,149.13,2` within 2 km

Put `-` in front of a term to leave out what it matches, as in `-tag:work`.
''';

/// A search field bound to the shared [MediaFilter], saying how many of
/// [total] items the search leaves when [shown] is given.

class FilterBar extends StatefulWidget {
  const FilterBar({super.key, this.shown, this.total});

  final int? shown;

  final int? total;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  late final MediaFilter _filter = context.read<MediaFilter>();

  late final TextEditingController _controller = TextEditingController(
    text: _filter.text,
  );

  @override
  void initState() {
    super.initState();
    _filter.addListener(_follow);
  }

  @override
  void dispose() {
    _filter.removeListener(_follow);
    _controller.dispose();
    super.dispose();
  }

  // Another section may have changed or cleared the search.

  void _follow() {
    if (_controller.text != _filter.text) _controller.text = _filter.text;
  }

  @override
  Widget build(BuildContext context) {
    final filter = context.watch<MediaFilter>();
    final problems = filter.search.problems;
    final shown = widget.shown;
    final total = widget.total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: TextField(
        controller: _controller,
        onChanged: (text) => filter.text = text,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.search),
          hintText:
              'Filter: beach  person:jane  tag:sunset  date:2026  '
              'location:yes',
          errorText: problems.isEmpty ? null : problems.first,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (filter.isActive && shown != null && total != null)
                Text(
                  '$shown of $total',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (filter.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear the filter',
                  onPressed: filter.clear,
                ),
              const MarkdownTooltip(
                message: filterHelp,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.help_outline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
