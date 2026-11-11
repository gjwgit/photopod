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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gap/gap.dart';
import 'package:provider/provider.dart';
import 'package:solidpod/solidpod.dart' show KeyManager, isUserLoggedIn;
import 'package:solidui/solidui.dart' show getKeyFromUserIfRequired;

import 'package:photopod/constants/app.dart';
import 'package:photopod/constants/media.dart';
import 'package:photopod/dialogs/album_name_dialog.dart';
import 'package:photopod/dialogs/download_media.dart';
import 'package:photopod/dialogs/info_dialog.dart';
import 'package:photopod/dialogs/message_dialog.dart';
import 'package:photopod/dialogs/preview_dialog.dart';
import 'package:photopod/dialogs/rename_dialog.dart';
import 'package:photopod/dialogs/share_dialog.dart';
import 'package:photopod/dialogs/view_options_dialog.dart';
import 'package:photopod/models/albums.dart';
import 'package:photopod/models/favourites.dart';
import 'package:photopod/models/library_section.dart';
import 'package:photopod/models/media_filter.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/view_prefs.dart';
import 'package:photopod/services/album_sharing.dart';
import 'package:photopod/services/analyser_inbox.dart';
import 'package:photopod/services/demo_library.dart';
import 'package:photopod/services/media_catalog.dart';
import 'package:photopod/services/media_index.dart';
import 'package:photopod/services/media_metadata_backfill.dart';
import 'package:photopod/services/media_renditions.dart';
import 'package:photopod/services/media_store.dart';
import 'package:photopod/services/people.dart';
import 'package:photopod/services/pod_keys.dart';
import 'package:photopod/services/pod_media_ops.dart';
import 'package:photopod/services/pod_media_service.dart';
import 'package:photopod/services/shared_with_me.dart';
import 'package:photopod/services/storage_upgrade.dart';
import 'package:photopod/services/tags.dart';
import 'package:photopod/services/thumbnail_cache.dart';
import 'package:photopod/services/video_frame.dart';
import 'package:photopod/utils/formatting.dart';
import 'package:photopod/utils/resource_name.dart';
import 'package:photopod/widgets/album_list.dart';
import 'package:photopod/widgets/demo_banner.dart';
import 'package:photopod/widgets/filter_bar.dart';
import 'package:photopod/widgets/media_grid.dart';
import 'package:photopod/widgets/media_list.dart';
import 'package:photopod/widgets/media_timeline.dart';
import 'package:photopod/widgets/media_toolbar.dart';
import 'package:photopod/widgets/pagination_bar.dart';

part 'media_browser_actions.dart';
part 'media_browser_albums.dart';
part 'media_browser_body.dart';
part 'media_browser_drop.dart';
part 'media_browser_transfers.dart';

/// The Library, Favourites, Albums or Videos section of the app.
///
/// One widget serves all four, because the only thing that differs is which
/// items are shown and how they are laid out. Each is a view over the whole
/// album at once, read from the shared [MediaIndex]. Selection and every
/// toolbar action behave identically in each.

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

  /// The URLs of the selected items.

  final Set<String> _selected = <String>{};

  /// In the Albums section, the album the selection was made in. A photo can
  /// sit in several albums at once, so the selection is kept to one album at
  /// a time, which is what lets Remove from album know which album to take
  /// it out of.

  String? _selectedAlbum;

  /// Whether several items can be selected at once, which the toolbar turns
  /// on and off. Otherwise a tap selects one item in place of the last.

  bool _multiSelect = false;

  /// The item tapped last, which is the one kept when **Select several** is
  /// turned off.

  String? _lastTapped;

  /// Where a shift-tap range starts from.

  int _anchor = 0;

  /// The page currently being shown, counting from zero.

  int _page = 0;

  /// What went wrong opening the album, if anything.

  String? _error;

  /// Whether nobody is logged in, so this section shows the bundled sample
  /// album rather than a Pod. See [DemoLibrary].

  bool _demo = false;

  /// Whether files are being dragged over the Library right now.

  bool _dragging = false;

  /// The search the items were last filtered by, so that a new one can go
  /// back to the first page.

  String _filterText = '';

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
      // PhotoPod skips the login screen, so a visitor who has not logged in
      // is shown the sample album, which needs no folder on any Pod.

      if (!await isUserLoggedIn()) {
        if (!mounted) return;
        setState(() {
          _demo = true;
          _root = DemoLibrary.root;
        });
        await reload();
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
      });
      await reload();

      // Anything an earlier build stored under the name the user gave it,
      // or filed in a folder, is moved into the store, once, as soon as the
      // security key is to hand.

      //
      // The faces and tags already found are read from the Pod at the same
      // point, so that People and Tags open on them and send only the photos
      // added since.

      unawaited(
        PodKeys.unlocked().then((_) async {
          if (mounted) unawaited(context.read<People>().preload());
          if (mounted) unawaited(context.read<PhotoTags>().preload());
          if (mounted) await _upgradeStorage(context);
        }),
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  /// Read what this section shows from the Pod again.
  ///
  /// Every section is a view over the whole album, which is scanned once and
  /// shared between them, so moving between sections reuses the last scan
  /// unless something has changed it or [force] says otherwise — which is
  /// what the Refresh button asks for.

  Future<void> reload({bool force = false}) async {
    // Another device may have renamed something since the names were read.

    if (force && !_demo) MediaCatalog.invalidate();

    // The names of the files are encrypted, so the key is asked for before
    // the album is listed rather than after, when the tiles would already be
    // showing the names they are stored under.

    if (!_demo && await MediaCatalog.needsKey() && mounted) {
      await _ensureSecurityKey(context);
    }
    if (!mounted) return;

    final index = context.read<MediaIndex>();

    // The albums are read once at login. Refresh reads them again, in case
    // another device has changed them since.

    if (force && widget.section == LibrarySection.albums) {
      final favourites = context.read<Favourites>();
      await context.read<Albums>().load();
      await favourites.load();
    }
    if (!mounted) return;
    await index.refresh(force: force);
    if (!mounted) return;

    // The keys are settled before the tiles appear, not after. A tile asks
    // for its thumbnail the moment it is built, and a page of them asking at
    // once is exactly what must not happen while solidpod is still reading
    // its key file for the first time.

    await _ensureKeyForEncrypted(index.items);
    if (!mounted) return;

    // Refreshing the albums is also when any sharing that fell behind — say,
    // a heart given from the preview — is caught up.

    if (force && !_demo && widget.section == LibrarySection.albums) {
      await _syncSharing(context);
      if (!mounted) return;
    }
    setState(
      () => _selected.removeWhere(
        (id) => !index.items.any((item) => item.id == id),
      ),
    );
    if (widget.section == LibrarySection.library) unawaited(_fillInDetails());
  }

  // Any photo added before the catalog kept its details has them filled in,
  // in the background, and the timeline is rearranged once its dates are
  // known. It waits until any upgrade of the album has finished, rather than
  // read thumbnails while their photos are being moved.

  Future<void> _fillInDetails() async {
    if (!_demo) await StorageUpgrade.settled;
    if (!mounted) return;
    final index = context.read<MediaIndex>();
    if (index.error != null) return;
    final recorded = await MediaMetadataBackfill.run(index.items);
    if (recorded > 0) index.applyDates();
  }

  // Every thumbnail of an encrypted photo has to be decrypted before it can
  // be shown. Asking for the security key once, here, beats letting each tile
  // fail on its own and leaving a grid of broken images, and reading the keys
  // into memory once, here, keeps a page of tiles from all reading them at
  // the same time.

  Future<void> _ensureKeyForEncrypted(List<MediaItem> items) async {
    if (!mounted) return;
    if (!items.any((item) => item.isEncrypted)) return;
    await _ensureSecurityKey(context);
  }

  /// Everything this section shows, before sorting, narrowed to what the
  /// filter bar is searching for.

  List<MediaItem> get _source => _filtered(_unfiltered);

  /// The items of [items] that match the filter bar's search.

  List<MediaItem> _filtered(List<MediaItem> items) {
    final search = context.read<MediaFilter>().search;
    if (search.isEmpty) return items;
    return items
        .where((item) => search.matches(item, MediaCatalog.entryOf(item.path)))
        .toList();
  }

  /// Everything this section shows, before filtering and sorting.
  ///
  /// The Library shows the whole album, with what other people have shared
  /// with the user among it, marked as shared. The other sections filter it.

  List<MediaItem> get _unfiltered {
    switch (widget.section) {
      case LibrarySection.library:
        return context.read<MediaIndex>().items;
      case LibrarySection.favourites:
        final favourites = context.read<Favourites>();
        return context
            .read<MediaIndex>()
            .items
            .where(favourites.contains)
            .toList();
      case LibrarySection.albums:
        // Favourites has its own section and is not listed among the albums.

        final albums = context.read<Albums>();
        final paths = {
          for (final name in albums.names) ...albums.pathsOf(name),
          for (final album in context.read<SharedWithMe>().albums)
            ...album.itemUrls,
        };
        return context
            .read<MediaIndex>()
            .items
            .where((item) => paths.contains(item.path))
            .toList();
      case LibrarySection.videos:
        return context.read<MediaIndex>().videos;
      case LibrarySection.people:
      case LibrarySection.tags:
      case LibrarySection.maps:
        return const [];
    }
  }

  /// Whether this section is still waiting on the Pod.

  bool get _isLoading => context.read<MediaIndex>().isLoading;

  /// What went wrong, if anything.

  String? get _errorText => _error ?? context.read<MediaIndex>().error;

  /// Whether the Library is showing its tiles as a timeline, one day under
  /// each heading. The Details view keeps its sortable, paged list.

  bool get _isTimeline =>
      widget.section == LibrarySection.library &&
      context.read<ViewPrefs>().viewMode == MediaViewMode.grid;

  /// Everything this section shows, folders first and then files, each group
  /// in the order the user has chosen.

  List<MediaItem> get _sorted {
    final option = context.read<ViewPrefs>().sortOption;
    final all = _source;
    final folders = all.where((item) => item.isFolder).toList();
    final files = all.where((item) => !item.isFolder).toList();

    // The timeline sets its own order, the latest day first, and the
    // selection and the preview follow the tiles as they are laid out.

    if (_isTimeline) {
      _sortInPlace(folders, MediaSortOption.nameAscending);
      return [
        ...folders,
        for (final group in groupByDay(files)) ...group.items,
      ];
    }
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

  // Items sort by when they were taken, where that is known. Those with no
  // date at all sort to the end of an ascending list, rather than jumping to
  // the front as the epoch would.

  static int _byDate(MediaItem a, MediaItem b) {
    final left = a.date;
    final right = b.date;
    if (left == null && right == null) return _byName(a, b);
    if (left == null) return 1;
    if (right == null) return -1;
    final result = left.compareTo(right);
    return result != 0 ? result : _byName(a, b);
  }

  /// The photos and videos this section shows, in the order they are
  /// displayed, which is what the preview's arrows step through.

  List<MediaItem> get _sortedFiles =>
      _sorted.where((item) => !item.isFolder).toList();

  /// The selected items, in the order they are displayed, so that "the first
  /// selected item" means what the user sees.

  List<MediaItem> get _selectedItems =>
      _sorted.where((item) => _selected.contains(item.id)).toList();

  /// The selected photos and videos, leaving out any selected folder.

  List<MediaItem> get _selectedFiles =>
      _selectedItems.where((item) => !item.isFolder).toList();

  /// Whether the selection was made in one of the user's own albums, which
  /// is the only kind anything can be taken out of. A shared album is
  /// identified by the URL of its file, a name of the user's never is.

  bool get _inOwnAlbum =>
      _selectedAlbum != null && !_selectedAlbum!.contains('://');

  @override
  Widget build(BuildContext context) => _buildBrowser(context);
}
