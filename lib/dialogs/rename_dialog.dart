/// Ask for a new name for a file or folder.
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
import 'package:photopod/models/media_item.dart';
import 'package:photopod/utils/name_validator.dart';

/// Ask for a new name for [item], returning it once it passes validation, or
/// null if the user cancels.
///
/// The name is checked before the dialogue closes, and an invalid one is
/// reported in its own error dialogue while the entry field stays open with
/// what was typed, so the user can correct it rather than start again.

Future<String?> showRenameDialog(BuildContext context, MediaItem item) =>
    showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(item: item),
    );

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.item});

  final MediaItem item;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.item.name,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text;
    final problem = validateName(
      name,
      isFolder: widget.item.isFolder,
      originalName: widget.item.isFolder ? null : widget.item.name,
    );

    if (problem != null) {
      await showErrorDialog(context, 'That name cannot be used', problem);
      return;
    }

    if (name == widget.item.name) {
      Navigator.of(context).pop();
      return;
    }

    if (mounted) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final noun = widget.item.isFolder ? 'folder' : 'file';

    return AlertDialog(
      title: Text('Rename $noun'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Currently called "${widget.item.name}".',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Gap(16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: maxNameLength,
            decoration: InputDecoration(
              labelText: 'New $noun name',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Rename')),
      ],
    );
  }
}
