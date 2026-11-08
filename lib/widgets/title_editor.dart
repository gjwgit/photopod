/// The editable title of a photo.
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

import 'package:photopod/models/catalog_entry.dart';

/// A field holding a photo's title, saved when the user presses Enter or
/// moves on.
///
/// A title a service suggested is marked with a sparkle and says who
/// suggested it, so that it is never mistaken for the user's own words;
/// editing it makes it the user's.

class TitleEditor extends StatefulWidget {
  const TitleEditor({super.key, required this.title, required this.onChanged});

  /// The title the photo has now, if any.

  final PhotoTitle? title;

  /// Called with what the user has written, once they are done with it, when
  /// it differs from [title]. Empty text takes the title away.

  final ValueChanged<String> onChanged;

  @override
  State<TitleEditor> createState() => _TitleEditorState();
}

class _TitleEditorState extends State<TitleEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.title?.text ?? '',
  );
  final FocusNode _focus = FocusNode();

  // What was last saved, or the title shown to begin with, so that pressing
  // Enter and then moving on saves only once.

  late String _saved = widget.title?.text ?? '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(TitleEditor old) {
    super.didUpdateWidget(old);

    // A title that changes from outside, such as one put back after a save
    // failed, is shown, unless the user is in the middle of typing.

    final text = widget.title?.text ?? '';
    if (text == (old.title?.text ?? '')) return;
    _saved = text;
    if (!_focus.hasFocus && _controller.text != text) _controller.text = text;
  }

  void _commit() {
    final text = _controller.text.trim();
    if (text == _saved) return;
    _saved = text;
    widget.onChanged(text);
  }

  // A title typed just before the dialogue was closed is kept, not lost.

  @override
  void dispose() {
    _commit();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final suggested = title != null && !title.isUsers;

    return TextField(
      controller: _controller,
      focusNode: _focus,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Add a title',
        prefixIcon: Icon(
          suggested ? Icons.auto_awesome : Icons.title,
          size: 18,
          color: suggested ? Theme.of(context).colorScheme.primary : null,
        ),
        helperText: suggested
            ? 'Suggested by ${title.source}. Edit it to make it yours.'
            : null,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => _commit(),
    );
  }
}
