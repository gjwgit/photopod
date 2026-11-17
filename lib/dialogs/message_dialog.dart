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

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

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
/// bar would be more noise than help.
///
/// The spinner's own route is held on to and removed by name, as it were,
/// rather than by popping whatever is on top. That way it is taken down even
/// when [action] ends before the spinner has been drawn, as merging two
/// copies that say the same thing does, and it never takes down a dialogue
/// opened over it instead. SolidUI's `LoadingDialogController` was used
/// before, but it learns how to close the spinner only once the spinner has
/// been built, so an action that ended sooner left the spinner up for good.
/// The route is removed through the root navigator captured at the start, so
/// it cannot be stranded when the calling widget is disposed mid-operation.
///
/// A long [message] stretches the dialogue across the whole window, so
/// [maxWidth] can hold it to a comfortable width, with an optional [title]
/// above it.

Future<T> showWorking<T>(
  BuildContext context,
  String message,
  Future<T> Function() action, {
  String? title,
  double? maxWidth,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final spinner = Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const CircularProgressIndicator(),
      const SizedBox(width: 16),
      Flexible(child: Text(message)),
    ],
  );
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: title == null ? null : Text(title),
        content: maxWidth == null
            ? spinner
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: spinner,
              ),
      ),
    ),
  );
  unawaited(navigator.push(route));
  try {
    return await action();
  } finally {
    if (navigator.mounted && route.isActive) navigator.removeRoute(route);
  }
}
