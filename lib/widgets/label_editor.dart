/// An editable row of labels, such as a photo's tags or the people in it.
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

import 'package:gap/gap.dart';

import 'package:photopod/models/catalog_entry.dart' show userSource;

/// One label: its text, who put it there — [userSource], or the service
/// that suggested it — and, for a suggestion, how sure the service was.

typedef PhotoLabel = ({String text, String source, double? confidence});

/// How many earlier labels are offered while the user types.

const int _maxSuggestions = 8;

/// The labels on one photo as chips, each with a cross to take it off, and
/// a field to add another.
///
/// A label a service suggested carries a sparkle, and says which service
/// and how sure it was, so that it is never mistaken for one the user chose.
/// While the user types, the labels already used on other photos are
/// offered, so that one person or place is always spelt the same way.

class LabelEditor extends StatefulWidget {
  const LabelEditor({
    super.key,
    required this.labels,
    required this.suggestions,
    required this.hint,
    required this.icon,
    required this.onAdd,
    required this.onRemove,
  });

  /// The labels on the photo now.

  final List<PhotoLabel> labels;

  /// Labels used elsewhere, offered as the user types.

  final Iterable<String> suggestions;

  /// What the field asks for, such as `Add a tag`.

  final String hint;

  /// The icon at the start of the field.

  final IconData icon;

  /// Called with a label the user has added.

  final ValueChanged<String> onAdd;

  /// Called with the position of a label the user has taken off.

  final ValueChanged<int> onRemove;

  @override
  State<LabelEditor> createState() => _LabelEditorState();
}

class _LabelEditorState extends State<LabelEditor> {
  // The field's own controller, which [Autocomplete] makes, kept so that the
  // field can be emptied once a suggestion is chosen.

  TextEditingController? _field;
  Iterable<String> _options(TextEditingValue value) {
    final query = value.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final present = {
      for (final label in widget.labels) label.text.toLowerCase(),
    };
    return widget.suggestions
        .where(
          (each) =>
              each.toLowerCase().contains(query) &&
              !present.contains(each.toLowerCase()),
        )
        .take(_maxSuggestions);
  }

  void _add(String text, TextEditingController controller) {
    final label = text.trim();
    controller.clear();
    if (label.isNotEmpty) widget.onAdd(label);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.labels.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (index, label) in widget.labels.indexed)
                Tooltip(
                  message: label.source == userSource
                      ? 'Added by you'
                      : 'Suggested by ${label.source}'
                            '${label.confidence == null ? '' : ' (${(label.confidence! * 100).round()}% sure)'}'
                            '. Take it off if it is wrong.',
                  child: InputChip(
                    label: Text(label.text),
                    avatar: label.source == userSource
                        ? null
                        : Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: scheme.primary,
                          ),
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => widget.onRemove(index),
                    deleteButtonTooltipMessage: 'Remove "${label.text}"',
                  ),
                ),
            ],
          ),
          const Gap(8),
        ],
        Autocomplete<String>(
          optionsBuilder: _options,
          fieldViewBuilder: (context, controller, focusNode, _) => TextField(
            controller: _field = controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.hint,
              prefixIcon: Icon(widget.icon, size: 18),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (text) {
              _add(text, controller);
              focusNode.requestFocus();
            },
          ),
          onSelected: (choice) {
            _field?.clear();
            widget.onAdd(choice);
          },
        ),
      ],
    );
  }
}
