/// The dialogue for naming a person.
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

import 'package:photopod/services/people.dart';
import 'package:photopod/widgets/face_avatar.dart';

/// Ask what [person] is called, returning the name typed, which may be
/// blank to forget it, or null if the user cancels.

Future<String?> showPersonNameDialog(
  BuildContext context,
  PersonEntry person,
) => showDialog<String>(
  context: context,
  builder: (context) => _PersonNameDialog(person: person),
);

/// The name field lives in a State of its own so that its controller is
/// disposed only once the dialogue has finished closing: disposing it as
/// soon as the dialogue returned left the closing animation building a
/// TextField with a dead controller.

class _PersonNameDialog extends StatefulWidget {
  const _PersonNameDialog({required this.person});

  final PersonEntry person;

  @override
  State<_PersonNameDialog> createState() => _PersonNameDialogState();
}

class _PersonNameDialogState extends State<_PersonNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.person.name ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        FaceAvatar(
          face: widget.person.portrait,
          item: widget.person.portraitItem,
          size: 40,
        ),
        const Gap(12),
        const Text('Name this person'),
      ],
    ),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(hintText: 'Name'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}
