/// Ask for the name of an album.
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

import 'package:gap/gap.dart';

import 'package:photopod/dialogs/message_dialog.dart';
import 'package:photopod/models/albums.dart';
import 'package:photopod/utils/name_validator.dart';

/// Ask for the name of a new album, or a new name for the album called
/// [current], returning it once it passes validation, or null if the user
/// cancels or leaves the name as it was.
///
/// [existing] is every album already there, which the new name may not
/// repeat. [selectedCount] says how many selected items a new album will be
/// given, so the dialogue can say so.

Future<String?> showAlbumNameDialog(
  BuildContext context, {
  required Iterable<String> existing,
  String? current,
  int selectedCount = 0,
}) => showDialog<String>(
  context: context,
  builder: (context) => _AlbumNameDialog(
    existing: existing.toList(),
    current: current,
    selectedCount: selectedCount,
  ),
);

class _AlbumNameDialog extends StatefulWidget {
  const _AlbumNameDialog({
    required this.existing,
    required this.current,
    required this.selectedCount,
  });

  final List<String> existing;
  final String? current;
  final int selectedCount;

  @override
  State<_AlbumNameDialog> createState() => _AlbumNameDialogState();
}

class _AlbumNameDialogState extends State<_AlbumNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current ?? '',
  );

  bool get _renaming => widget.current != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text;
    if (name == widget.current) {
      Navigator.of(context).pop();
      return;
    }

    final problem = validateAlbumName(
      name,
      existing: widget.existing,
      current: widget.current,
    );
    if (problem != null) {
      await showErrorDialog(context, 'That name cannot be used', problem);
      return;
    }
    if (mounted) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.selectedCount;
    final note = _renaming
        ? 'Currently called "${widget.current}".'
        : count == 0
        ? null
        : count == 1
        ? 'The selected item will be put into the new album.'
        : 'The $count selected items will be put into the new album.';

    return AlertDialog(
      title: Text(_renaming ? 'Rename album' : 'Create new album'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note != null) ...[
              Text(note, style: Theme.of(context).textTheme.bodySmall),
              const Gap(16),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: maxNameLength,
              decoration: const InputDecoration(
                labelText: 'Album name',
                helperText: "Letters, digits and - _ . ! ~ ' ( ) only",
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_renaming ? 'Rename' : 'Create'),
        ),
      ],
    );
  }
}
