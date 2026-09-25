/// Report problems and ask for confirmation.
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

import 'package:solidui/solidui.dart' show LoadingDialogController;

/// Tell the user that something could not be done, and why.
///
/// Every failed Pod operation ends here, so that a server refusal, a missing
/// destination or an invalid name are all reported the same way rather than
/// disappearing into a transient snack bar.

Future<void> showErrorDialog(
  BuildContext context,
  String title,
  String message,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    icon: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  ),
);

/// Ask the user to confirm an action that cannot be undone. Returns true only
/// when they choose to go ahead.

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Show a modal spinner with [message] while [action] runs, and take it away
/// again however the action ends.
///
/// Copying an album or uploading a video takes long enough that the user
/// needs to see that something is happening, and short enough that a progress
/// bar would be more noise than help. SolidUI's controller is used because it
/// pops the dialog through the dialog's own context, so the spinner cannot be
/// stranded when the calling widget is disposed mid-operation.

Future<T> showWorking<T>(
  BuildContext context,
  String message,
  Future<T> Function() action,
) async {
  final loading = LoadingDialogController.show(
    context: context,
    message: message,
  );
  try {
    return await action();
  } finally {
    loading.close();
  }
}
