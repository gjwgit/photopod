/// Browse the photos and videos held in the Pod.
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
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:gap/gap.dart';
import 'package:provider/provider.dart';
import 'package:solidpod/solidpod.dart' show KeyManager, isUserLoggedIn;
import 'package:solidui/solidui.dart' show getKeyFromUserIfRequired;

import 'package:photopod/constants/media.dart';
import 'package:photopod/dialogs/destination_dialog.dart';
import 'package:photopod/dialogs/folder_name_dialog.dart';
import 'package:photopod/dialogs/info_dialog.dart';
import 'package:photopod/dialogs/message_dialog.dart';
import 'package:photopod/dialogs/preview_dialog.dart';
import 'package:photopod/dialogs/rename_dialog.dart';
import 'package:photopod/dialogs/share_dialog.dart';
import 'package:photopod/dialogs/view_options_dialog.dart';
import 'package:photopod/models/favourites.dart';
import 'package:photopod/models/library_section.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/view_prefs.dart';
import 'package:photopod/services/media_index.dart';
import 'package:photopod/services/pod_media_ops.dart';
import 'package:photopod/services/pod_media_service.dart';
import 'package:photopod/services/thumbnail_cache.dart';
import 'package:photopod/utils/destination_path.dart';
import 'package:photopod/utils/formatting.dart';
import 'package:photopod/widgets/breadcrumb_bar.dart';
import 'package:photopod/widgets/media_grid.dart';
import 'package:photopod/widgets/media_list.dart';
import 'package:photopod/widgets/media_toolbar.dart';
import 'package:photopod/widgets/pagination_bar.dart';

part 'media_browser_actions.dart';
part 'media_browser_body.dart';
part 'media_browser_transfers.dart';

/// The Library, Favourites or Videos section of the app.
///
/// One widget serves all three, because the only thing that differs is where
/// the items come from. The Library walks the folders in the Pod and shows
/// one of them at a time; Favourites and Videos are filters over the whole
/// album at once, and so read from the shared [MediaIndex] instead. Selection,
/// the tiles and every toolbar action behave identically in each.

class MediaBrowser extends StatefulWidget {
  const MediaBrowser({super.key, required this.section});

  /// Which of the sections this instance is showing.

  final LibrarySection section;

  @override
  State<MediaBrowser> createState() => MediaBrowserState();
}

class MediaBrowserState extends State<MediaBrowser> {
  /// The Pod-relative path of the album root, `photopod/data`.

  String _root = '';

  /// The Pod-relative path of the folder currently being shown. Only the
  /// Library moves away from the root.

  String _path = '';

  /// Everything in the current folder, unsorted. Used by the Library only;
  /// the other sections read from the album index.

  List<MediaItem> _items = const [];

  /// The URLs of the selected items.

  final Set<String> _selected = <String>{};

  /// Where a shift-tap range starts from.

  int _anchor = 0;

  /// The page currently being shown, counting from zero.

  int _page = 0;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Rebuild after [change] has altered the state.
  ///
  /// [State.setState] is protected, and the toolbar actions live in
  /// extensions in the other halves of this library, so they go through this
  /// rather than reaching into a member they are not entitled to.

  void updateState(VoidCallback change) => setState(change);

  Future<void> _start() async {
    try {
      if (!await isUserLoggedIn()) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error =
                'Please log in to your Pod to see your '
                '${widget.section.noun}.';
          });
        }
        return;
      }

      final root = await PodMediaService.rootPath();

      // The album folder is created on first use rather than being assumed,
      // so a Pod that has never run PhotoPod opens on an empty album instead
      // of an error.

      await PodMediaService.ensureFolder(await PodMediaService.folderUrl(root));

      if (!mounted) return;
      setState(() {
        _root = root;
        _path = root;
      });
      await reload();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Read what this section shows from the Pod again.
  ///
  /// The Library re-reads the one folder it is looking at. The flat sections
  /// walk the whole album, which is the only way to answer "every favourite"
  /// or "every video" across folders.
  ///
  /// Only the section being looked at is built, so moving between sections
  /// starts each one afresh. A walk of the whole album is far too expensive
  /// to repeat every time the user taps Favourites, so the flat sections
  /// reuse the last scan unless something has changed it or [force] says
  /// otherwise — which is what the Refresh button asks for.

  Future<void> reload({bool force = false}) async {
    if (!widget.section.browsesFolders) {
      final index = context.read<MediaIndex>();
      await index.refresh(force: force);
      if (!mounted) return;
      setState(
        () => _selected.removeWhere(
          (id) => !index.items.any((item) => item.id == id),
        ),
      );
      await _ensureKeyForEncrypted(index.items);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await PodMediaService.listFolder(
        _path,
        kinds: widget.section.kinds,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _selected.removeWhere((id) => !items.any((item) => item.id == id));
      });
      await _ensureKeyForEncrypted(items);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // Every thumbnail of an encrypted photo has to be decrypted before it can
  // be shown. Asking for the security key once, here, beats letting each tile
  // fail on its own and leaving a grid of broken images.

  Future<void> _ensureKeyForEncrypted(List<MediaItem> items) async {
    if (!mounted) return;
    if (items.any((item) => item.isEncrypted)) {
      await _ensureSecurityKey(context);
    }
  }

  /// Move to [path], clearing the selection and returning to the first page.

  Future<void> _goTo(String path) async {
    setState(() {
      _path = path;
      _page = 0;
      _selected.clear();
      _anchor = 0;
    });
    await reload();
  }

  /// The folder names between the album root and where the user is now.

  List<String> get _segments {
    if (_path == _root || _root.isEmpty) return const [];
    final prefix = '$_root/';
    if (!_path.startsWith(prefix)) return const [];
    return _path.substring(prefix.length).split('/');
  }

  /// The same folder names, decoded so the breadcrumb trail reads as the user
  /// named the folders rather than as the server spells them.

  List<String> get _segmentLabels =>
      _segments.map(PodMediaService.decodeName).toList();

  /// Everything this section shows, before sorting.
  ///
  /// The Library reports the folder it is looking at. Favourites and Videos
  /// filter the album index, so both show items from every folder at once and
  /// neither shows a folder of its own.

  List<MediaItem> get _source {
    switch (widget.section) {
      case LibrarySection.library:
        return _items;
      case LibrarySection.favourites:
        final favourites = context.read<Favourites>();
        return context
            .read<MediaIndex>()
            .items
            .where(favourites.contains)
            .toList();
      case LibrarySection.videos:
        return context.read<MediaIndex>().videos;
      case LibrarySection.maps:
        return const [];
    }
  }

  /// Whether this section is still waiting on the Pod.

  bool get _isLoading => widget.section.browsesFolders
      ? _loading
      : context.read<MediaIndex>().isLoading;

  /// What went wrong, if anything.

  String? get _errorText => widget.section.browsesFolders
      ? _error
      : _error ?? context.read<MediaIndex>().error;

  /// Everything this section shows, folders first and then files, each group
  /// in the order the user has chosen.

  List<MediaItem> get _sorted {
    final option = context.read<ViewPrefs>().sortOption;
    final all = _source;
    final folders = all.where((item) => item.isFolder).toList();
    final files = all.where((item) => !item.isFolder).toList();
    _sortInPlace(folders, option);
    _sortInPlace(files, option);
    return [...folders, ...files];
  }

  static void _sortInPlace(List<MediaItem> items, MediaSortOption option) {
    switch (option) {
      case MediaSortOption.nameAscending:
        items.sort(_byName);
      case MediaSortOption.nameDescending:
        items.sort((a, b) => _byName(b, a));
      case MediaSortOption.dateAscending:
        items.sort(_byDate);
      case MediaSortOption.dateDescending:
        items.sort((a, b) => _byDate(b, a));
    }
  }

  static int _byName(MediaItem a, MediaItem b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  // Items the server gave no date for sort to the end of an ascending list,
  // rather than jumping to the front as the epoch would.

  static int _byDate(MediaItem a, MediaItem b) {
    final left = a.modified;
    final right = b.modified;
    if (left == null && right == null) return _byName(a, b);
    if (left == null) return 1;
    if (right == null) return -1;
    final result = left.compareTo(right);
    return result != 0 ? result : _byName(a, b);
  }

  /// The selected items, in the order they are displayed, so that "the first
  /// selected item" means what the user sees.

  List<MediaItem> get _selectedItems =>
      _sorted.where((item) => _selected.contains(item.id)).toList();

  /// The selected photos and videos, leaving out any selected folder.

  List<MediaItem> get _selectedFiles =>
      _selectedItems.where((item) => !item.isFolder).toList();

  @override
  Widget build(BuildContext context) => _buildBrowser(context);
}
