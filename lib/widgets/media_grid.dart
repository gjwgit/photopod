/// The wall of tiles the album is presented as.
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

import 'package:photopod/models/media_item.dart';
import 'package:photopod/widgets/media_thumbnail.dart';

/// Lay [items] out as square tiles, photos and videos mixed together.
///
/// File names are deliberately absent. An album is looked at, not read, and
/// a caption under every tile turns a wall of pictures into a list of
/// filenames; the name is still a hover away, and Get Info has it in full.
/// Folders are the exception — a folder tile with no name says nothing at
/// all — so those keep their label.

class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.isSelected,
    required this.isFavourite,
    required this.onTap,
    required this.onActivate,
    required this.onToggleFavourite,
    this.tileExtent = 140,
  });

  /// The folders and files on the current page.

  final List<MediaItem> items;

  /// Whether an item is part of the current selection.

  final bool Function(MediaItem) isSelected;

  /// Whether an item carries a heart.

  final bool Function(MediaItem) isFavourite;

  /// Called on a single tap, which changes the selection.

  final void Function(MediaItem) onTap;

  /// Called on a double tap, which opens a folder or previews a file.

  final void Function(MediaItem) onActivate;

  /// Called when the heart on a tile is tapped.

  final void Function(MediaItem) onToggleFavourite;

  /// The widest a tile may be, from the user's View preferences.

  final double tileExtent;

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(12),
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: tileExtent,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
    ),
    itemCount: items.length,
    itemBuilder: (context, index) {
      final item = items[index];
      return MediaTile(
        item: item,
        selected: isSelected(item),
        favourite: isFavourite(item),
        onTap: () => onTap(item),
        onActivate: () => onActivate(item),
        onToggleFavourite: () => onToggleFavourite(item),
      );
    },
  );
}

/// One square in the wall.
///
/// The picture fills the tile edge to edge and is cropped to the square, as
/// every photo application does, so the grid reads as a grid rather than as a
/// row of differently shaped pictures. Selection is shown by an outline and a
/// tick, and the heart appears on hover, when the item is already a
/// favourite, or when the tile is selected.

class MediaTile extends StatefulWidget {
  const MediaTile({
    super.key,
    required this.item,
    required this.selected,
    required this.favourite,
    required this.onTap,
    required this.onActivate,
    required this.onToggleFavourite,
  });

  /// The folder or file this tile stands for.

  final MediaItem item;

  /// Whether the item is part of the current selection.

  final bool selected;

  /// Whether the item carries a heart.

  final bool favourite;

  /// Called on a single tap.

  final VoidCallback onTap;

  /// Called on a double tap.

  final VoidCallback onActivate;

  /// Called when the heart is tapped.

  final VoidCallback onToggleFavourite;

  @override
  State<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<MediaTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;

    return Tooltip(
      message: item.name,
      waitDuration: const Duration(milliseconds: 700),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: widget.onActivate,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  color: scheme.surfaceContainerHighest,
                  child: item.isFolder
                      ? _buildFolder(context)
                      : MediaThumbnail(item: item),
                ),
              ),

              // The selection outline is drawn over the picture rather than
              // around it, so that selecting a tile never nudges its
              // neighbours.
              if (widget.selected)
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: scheme.primary, width: 3),
                  ),
                ),

              if (item.isVideo)
                const Positioned(left: 4, bottom: 4, child: _VideoBadge()),

              if (widget.selected)
                Positioned(
                  top: 4,
                  left: 4,
                  child: _Badge(
                    icon: Icons.check,
                    colour: scheme.onPrimary,
                    background: scheme.primary,
                  ),
                ),

              if (!item.isFolder &&
                  (widget.favourite || _hovering || widget.selected))
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _HeartButton(
                    favourite: widget.favourite,
                    onPressed: widget.onToggleFavourite,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // A folder cannot be pictured, so its tile is a card with the name on it.

  Widget _buildFolder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: FittedBox(
              child: Icon(Icons.folder, color: scheme.onSecondaryContainer),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSecondaryContainer),
          ),
        ],
      ),
    );
  }
}

class _HeartButton extends StatelessWidget {
  const _HeartButton({required this.favourite, required this.onPressed});

  final bool favourite;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: favourite ? 'Remove from Favourites' : 'Add to Favourites',
    button: true,
    child: IconButton(
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      tooltip: favourite ? 'Remove from Favourites' : 'Add to Favourites',
      icon: Icon(
        favourite ? Icons.favorite : Icons.favorite_border,
        color: favourite ? const Color(0xFFE53935) : Colors.white,

        // Photos are rarely a uniform colour, so the heart carries its own
        // shadow rather than relying on the picture behind it.
        shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
      ),
      onPressed: onPressed,
    ),
  );
}

class _VideoBadge extends StatelessWidget {
  const _VideoBadge();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black45,
      borderRadius: BorderRadius.all(Radius.circular(10)),
    ),
    child: Padding(
      padding: EdgeInsets.all(3),
      child: Icon(Icons.play_arrow, size: 14, color: Colors.white),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.colour,
    required this.background,
  });

  final IconData icon;
  final Color colour;
  final Color background;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: background, shape: BoxShape.circle),
    child: Padding(
      padding: const EdgeInsets.all(2),
      child: Icon(icon, size: 14, color: colour),
    ),
  );
}
