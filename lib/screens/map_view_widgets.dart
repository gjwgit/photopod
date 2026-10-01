/// The markers, dialogue and notices drawn on the map.
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

part of 'map_view.dart';

/// One spot on the map and the photos taken there.

class _Place {
  const _Place({required this.point, required this.items});

  final LatLng point;
  final List<MediaItem> items;
}

class _PlaceMarker extends StatelessWidget {
  const _PlaceMarker({required this.place, required this.onTap});

  final _Place place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: place.items.length == 1
            ? place.items.first.name
            : '${place.items.length} photos',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(blurRadius: 4, color: Colors.black38),
                ],
              ),
              child: ClipOval(
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: MediaThumbnail(item: place.items.first),
                  ),
                ),
              ),
            ),
            if (place.items.length > 1)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: Text(
                    '${place.items.length}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The photos taken at one spot, offered as thumbnails to choose from.

class _PlaceDialog extends StatelessWidget {
  const _PlaceDialog({required this.place});

  final _Place place;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${place.items.length} photos taken here'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in place.items)
              Tooltip(
                message: mediaTooltipText(item),
                child: InkWell(
                  onTap: () async {
                    Navigator.of(context).pop();
                    await showPreviewDialog(context, item);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 92,
                      height: 92,
                      child: ColoredBox(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: MediaThumbnail(item: item),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSecondaryContainer);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: scheme.onSecondaryContainer),
                const Gap(8),
              ],
              Flexible(child: Text(text, style: style)),
            ],
          ),
        ),
      ),
    );
  }
}
