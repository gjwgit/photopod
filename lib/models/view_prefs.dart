/// How the media browser lays items out.
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

import 'package:shared_preferences/shared_preferences.dart';

/// How items are laid out in the main content area.

enum MediaViewMode {
  /// Photos and videos as a wall of tiles, the way a photo album is usually
  /// looked at. No file names, so nothing competes with the pictures.

  grid('Tiles', Icons.grid_view),

  /// One row per item, with name, size and date in separate columns.

  list('Details', Icons.view_list);

  /// Label shown in the View dialogue.

  final String label;

  /// Icon shown beside the label.

  final IconData icon;

  const MediaViewMode(this.label, this.icon);
}

/// The orders the browser can present folders and files in.
///
/// Folders always sort ahead of files so that navigation stays predictable,
/// and the chosen order is then applied within each of the two groups.

enum MediaSortOption {
  /// By name, A to Z.

  nameAscending('File name', 'A → Z'),

  /// By name, Z to A.

  nameDescending('File name', 'Z → A'),

  /// By the time the server last recorded a change, oldest first.

  dateAscending('Creation time', 'Oldest first'),

  /// By the time the server last recorded a change, newest first.

  dateDescending('Creation time', 'Newest first');

  /// The field being sorted on.

  final String fieldLabel;

  /// The direction of the sort.

  final String directionLabel;

  const MediaSortOption(this.fieldLabel, this.directionLabel);

  /// Combined label suitable for a menu entry.

  String get displayLabel => '$fieldLabel: $directionLabel';
}

/// How big a tile is in the tiled layout.
///
/// The value is the widest a tile may be; the grid fits as many of them
/// across the window as will go and shares out what is left over, so the
/// tiles stay square whatever the window is doing.

enum MediaTileSize {
  /// A contact sheet: a great many photos at once.

  small('Small', 96),

  /// The default, which suits a desktop window and a tablet alike.

  medium('Medium', 140),

  /// Fewer, bigger tiles, which is what a phone wants.

  large('Large', 200);

  /// Label shown in the View dialogue.

  final String label;

  /// The widest a tile may be, in logical pixels.

  final double extent;

  const MediaTileSize(this.label, this.extent);
}

/// The page sizes offered in the View dialogue.

const List<int> pageSizeChoices = [20, 50, 100, 200];

/// Device-local display preferences for the media browser.
///
/// These describe how the user likes to look at their album on this
/// particular device, so they are held in shared preferences and never
/// written to the Pod.

class ViewPrefs extends ChangeNotifier {
  static const _viewModeKey = 'photopod.viewMode';
  static const _sortKey = 'photopod.sortOption';
  static const _pageSizeKey = 'photopod.itemsPerPage';
  static const _tileSizeKey = 'photopod.tileSize';

  MediaViewMode _viewMode = MediaViewMode.grid;
  MediaSortOption _sortOption = MediaSortOption.nameAscending;
  MediaTileSize _tileSize = MediaTileSize.medium;
  int _itemsPerPage = pageSizeChoices.first;

  /// The current layout.

  MediaViewMode get viewMode => _viewMode;

  /// The current ordering.

  MediaSortOption get sortOption => _sortOption;

  /// How big the tiles are in the tiled layout.

  MediaTileSize get tileSize => _tileSize;

  /// How many items are shown on one page.

  int get itemsPerPage => _itemsPerPage;

  /// Load the stored preferences, falling back to the defaults when nothing
  /// has been saved yet or when the stored value is no longer valid.

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _viewMode =
        _byName(MediaViewMode.values, prefs.getString(_viewModeKey)) ??
        _viewMode;
    _sortOption =
        _byName(MediaSortOption.values, prefs.getString(_sortKey)) ??
        _sortOption;
    _tileSize =
        _byName(MediaTileSize.values, prefs.getString(_tileSizeKey)) ??
        _tileSize;
    final stored = prefs.getInt(_pageSizeKey);
    if (stored != null && pageSizeChoices.contains(stored)) {
      _itemsPerPage = stored;
    }
    notifyListeners();
  }

  /// Switch between the thumbnail grid and the detailed list.

  Future<void> setViewMode(MediaViewMode mode) async {
    if (mode == _viewMode) return;
    _viewMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewModeKey, mode.name);
  }

  /// Change the order items are presented in.

  Future<void> setSortOption(MediaSortOption option) async {
    if (option == _sortOption) return;
    _sortOption = option;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortKey, option.name);
  }

  /// Change how big the tiles are.

  Future<void> setTileSize(MediaTileSize size) async {
    if (size == _tileSize) return;
    _tileSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tileSizeKey, size.name);
  }

  /// Change how many items appear on a page.

  Future<void> setItemsPerPage(int count) async {
    if (count == _itemsPerPage || !pageSizeChoices.contains(count)) return;
    _itemsPerPage = count;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pageSizeKey, count);
  }

  static T? _byName<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
