/// Choose a destination folder for a copy or a move.
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
import 'package:photopod/services/pod_media_ops.dart';
import 'package:photopod/services/pod_media_service.dart';
import 'package:photopod/utils/destination_path.dart';
import 'package:photopod/utils/name_validator.dart';

/// Ask where a copy or move should put its items.
///
/// The destination can be typed or picked by walking the folders under
/// `photopod/data`. Whichever way it is given, it is checked against the Pod
/// before the dialogue closes: a path that does not exist is reported and the
/// dialogue stays open, so the operation never starts without somewhere to
/// put its files.
///
/// Returns the Pod-relative destination path, or null if the user cancels.

Future<Destination?> showDestinationDialog(
  BuildContext context, {
  required String rootPath,
  required String startPath,
  required String title,
  required String actionLabel,
  String? renameableFile,
}) => showDialog<Destination>(
  context: context,
  builder: (context) => _DestinationDialog(
    rootPath: rootPath,
    startPath: startPath,
    title: title,
    actionLabel: actionLabel,
    renameableFile: renameableFile,
  ),
);

/// What the Pod holds at a destination the user has given.

enum _Destination {
  /// A folder, which is what the operation needs.

  folder,

  /// A file, so the user has named an item rather than a place.
  file,

  /// Nothing at all, so it can be created.
  missing,
}

class _DestinationDialog extends StatefulWidget {
  const _DestinationDialog({
    required this.rootPath,
    required this.startPath,
    required this.title,
    required this.actionLabel,
    this.renameableFile,
  });

  final String rootPath;
  final String startPath;
  final String title;
  final String actionLabel;

  /// The name of the one file being copied or moved, when the selection is a
  /// single file and so can be given a new name on the way. Null when the
  /// selection is anything else, which makes a typed file name an error.

  final String? renameableFile;

  @override
  State<_DestinationDialog> createState() => _DestinationDialogState();
}

class _DestinationDialogState extends State<_DestinationDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: _relative(widget.startPath),
  );

  List<MediaItem> _folders = [];
  bool _loading = true;
  String _browsing = '';

  @override
  void initState() {
    super.initState();
    _browsing = _relative(widget.startPath);
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // The text field holds a path as the user would write it, while the paths
  // handed to the Pod carry percent-escaped segments. These two convert
  // between the pair, so that a folder called "Family Holiday" can be typed
  // and picked with a space in it.

  String _relative(String path) {
    if (path == widget.rootPath) return '';
    final prefix = '${widget.rootPath}/';
    final tail = path.startsWith(prefix) ? path.substring(prefix.length) : path;
    return tail.split('/').map(PodMediaService.decodeName).join('/');
  }

  Destination? _absolute(String relative) =>
      resolveDestination(widget.rootPath, relative);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await PodMediaService.listFolder(
        _absolute(_browsing)?.folderPath ?? widget.rootPath,
      );
      if (!mounted) return;
      final folders = items.where((item) => item.isFolder).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _folders = [];
        _loading = false;
      });
    }
  }

  void _browseTo(String relative) {
    setState(() {
      _browsing = relative;
      _controller.text = relative;
    });
    _load();
  }

  Future<void> _confirm() async {
    final destination = _absolute(_controller.text);

    if (destination == null) {
      await showErrorDialog(
        context,
        'Destination not allowed',
        'The destination has to stay inside "${widget.rootPath}". Remove the '
            '".." from the path and choose a folder within your album.',
      );
      return;
    }

    if (destination.renames && !await _nameIsUsable(destination.newName!)) {
      return;
    }

    final _Destination found;
    try {
      found = await _inspect(destination.folderPath);
    } on Object catch (e) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        'Could not check the destination',
        'The Pod could not be reached to confirm that '
            '"${destination.folderPath}" exists.\n\n$e',
      );
      return;
    }

    if (!mounted) return;

    switch (found) {
      case _Destination.folder:
        Navigator.of(context).pop(destination);

      case _Destination.file:
        await showErrorDialog(
          context,
          'That is a file, not a folder',
          'There is already a file at "${destination.folderPath}". The '
              'destination is the folder the items should be put INTO. '
              'Choose a folder such as "${widget.rootPath}", or one inside '
              'it, and add a file name after it only to rename what you are '
              'copying.',
        );

      case _Destination.missing:
        await _offerToCreate(destination);
    }
  }

  /// Whether [newName] may be given to the file being copied or moved,
  /// reporting the reason if not.
  ///
  /// Only one file can be given a name, and the same rules apply as to a
  /// rename, so a photo cannot be turned into a video by way of a copy.

  Future<bool> _nameIsUsable(String newName) async {
    final original = widget.renameableFile;

    if (original == null) {
      await showErrorDialog(
        context,
        'Cannot rename this selection',
        'Ending the destination with a file name renames what is copied, '
            'which only works when a single file is selected. Give a folder '
            'instead, or end the path with "/" if that is a folder name.',
      );
      return false;
    }

    final problem = validateName(
      newName,
      isFolder: false,
      originalName: original,
    );
    if (problem != null) {
      await showErrorDialog(context, 'That name cannot be used', problem);
      return false;
    }

    return true;
  }

  /// What, if anything, is at [destination] on the Pod.

  Future<_Destination> _inspect(String destination) async {
    if (await PodMediaService.folderExists(
      await PodMediaService.folderUrl(destination),
    )) {
      return _Destination.folder;
    }

    // Typing the path of a photo instead of the folder to put it in is an
    // easy mistake, and worth naming precisely rather than reporting as a
    // missing folder.

    final slash = destination.lastIndexOf('/');
    if (slash > 0) {
      final parent = destination.substring(0, slash);
      final leaf = PodMediaService.decodeName(destination.substring(slash + 1));
      if (await PodMediaService.mediaExists(parent, leaf)) {
        return _Destination.file;
      }
    }

    return _Destination.missing;
  }

  /// Offer to create a destination that is not there yet.
  ///
  /// An album often has no subfolders at all, so refusing an unknown path
  /// would leave the user with nowhere to copy to and no way to make one.

  Future<void> _offerToCreate(Destination destination) async {
    final problem = _invalidSegment(destination.folderPath);
    if (problem != null) {
      await showErrorDialog(context, 'Destination not allowed', problem);
      return;
    }

    final create = await showConfirmDialog(
      context,
      title: 'Create this folder?',
      message:
          'There is no folder at "$destination" on your Pod. Create it '
          'and continue?',
      confirmLabel: 'Create',
      destructive: false,
    );
    if (!create || !mounted) return;

    try {
      await PodMediaOps.createFolderPath(
        widget.rootPath,
        destination.folderPath,
      );
    } on Object catch (e) {
      if (mounted) {
        await showErrorDialog(context, 'Could not create the folder', '$e');
      }
      return;
    }

    if (mounted) Navigator.of(context).pop(destination);
  }

  /// The reason a folder along [destination] cannot be created, or null when
  /// every name is usable.

  String? _invalidSegment(String destination) {
    final tail = destination
        .substring(widget.rootPath.length)
        .split('/')
        .where((segment) => segment.isNotEmpty);

    for (final segment in tail) {
      final name = PodMediaService.decodeName(segment);
      final problem = validateName(name, isFolder: true);
      if (problem != null) {
        return '"$name" cannot be used as a folder name. $problem';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final parent = _browsing.contains('/')
        ? _browsing.substring(0, _browsing.lastIndexOf('/'))
        : '';

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Destination folder',

                helperText: widget.renameableFile == null
                    ? 'The folder to put the items in, always inside '
                          '${widget.rootPath}. A folder that is not there yet '
                          'can be created.'
                    : 'The folder to put the file in, always inside '
                          '${widget.rootPath}. End with a file name to rename '
                          'it on the way.',

                helperMaxLines: 3,

                // The root is part of the decoration rather than the text, so
                // it cannot be edited away. Floating the label always keeps it
                // on screen even while the field is empty and unfocused.
                prefixText: '${widget.rootPath}/',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _confirm(),
            ),
            const Gap(12),
            Text(
              'Or pick a folder',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Gap(4),
            SizedBox(height: 240, child: _buildBrowser(parent)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _confirm, child: Text(widget.actionLabel)),
      ],
    );
  }

  Widget _buildBrowser(String parent) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      children: [
        if (_browsing.isNotEmpty)
          ListTile(
            dense: true,
            leading: const Icon(Icons.drive_folder_upload),
            title: const Text('..'),
            onTap: () => _browseTo(parent),
          ),
        if (_folders.isEmpty)
          const ListTile(
            dense: true,
            enabled: false,
            title: Text('No folders here'),
          ),
        for (final folder in _folders)
          ListTile(
            dense: true,
            leading: const Icon(Icons.folder),
            title: Text(folder.name),
            onTap: () => _browseTo(
              _browsing.isEmpty ? folder.name : '$_browsing/${folder.name}',
            ),
          ),
      ],
    );
  }
}
