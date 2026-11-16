/// The header of the media browser: the section title and the toolbar.
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

part of 'media_browser.dart';

/// The header along the top of [MediaBrowserState]'s section, kept apart
/// from the rest of its visual side so that neither file grows unwieldy.

extension MediaBrowserHeader on MediaBrowserState {
  // The title and the toolbar share a row on a wide window and stack on a
  // narrow one, so neither has to be squeezed or scrolled on a phone.

  Widget _buildHeader(BuildContext context) {
    final files = _selectedFiles;
    final leading = _buildSectionTitle(context);

    final toolbar = MediaToolbar(
      section: widget.section,
      selectionCount: _selected.length,
      fileCount: files.length,
      allFavourite: context.read<Favourites>().containsAll(files),
      sortOption: _sortShown,
      sortOptions: _sortChoices,
      actions: _actions(context),
      albumNames: context.read<Albums>().names,
      canRemoveFromAlbum: _inOwnAlbum && files.isNotEmpty,
      hasShared: _selectedItems.any((item) => item.isShared),
      multiSelect: _multiSelect,
    );

    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= wideHeaderWidth
          ? Row(
              children: [
                Expanded(child: leading),
                toolbar,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [leading, toolbar],
            ),
    );
  }

  // The flat sections have no folder to name, so the left of the header says
  // which of them is on screen and how far across the album it has looked.

  Widget _buildSectionTitle(BuildContext context) {
    final index = context.read<MediaIndex>();
    final scanned = index.scannedAt;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Icon(
            widget.section.icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const Gap(8),
          Text(
            widget.section.label,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (!index.isLoading) ...[
            const Gap(8),
            Text(
              _countLabel(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
          if (context.read<SharedWithMe>().error != null) ...[
            const Gap(8),
            Tooltip(
              message:
                  'What other people have shared with you could not be '
                  'read, so it may be missing.\n\n'
                  '${context.read<SharedWithMe>().error}',
              child: Icon(
                Icons.warning_amber_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          if (index.isTruncated) ...[
            const Gap(8),
            Tooltip(
              message:
                  'Only the first $maxScannedFolders folders of your album '
                  'were read, so some items may be missing.',
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
          if (scanned != null) ...[
            const Gap(12),
            Flexible(
              child: Text(
                'Album read at ${formatDateTime(scanned)}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // How many photos and videos the section holds, whatever the filter bar
  // is searching for, which says for itself how many of them it shows.

  String _countLabel() {
    final files = _unfiltered.where((item) => !item.isFolder).toList();
    final videos = files.where((item) => item.isVideo).length;
    final photos = files.length - videos;
    String count(int n, String noun) =>
        '${formatCount(n)} $noun${n == 1 ? '' : 's'}';
    if (photos == 0 && videos == 0) {
      return count(
        0,
        widget.section == LibrarySection.videos ? 'video' : 'photo',
      );
    }
    return [
      if (photos > 0) count(photos, 'photo'),
      if (videos > 0) count(videos, 'video'),
    ].join(', ');
  }
}
