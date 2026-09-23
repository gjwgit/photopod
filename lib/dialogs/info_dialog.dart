/// Everything known about one photo or video.
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

import 'package:gap/gap.dart';
import 'package:provider/provider.dart';

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/favourites.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/photo_metadata.dart';
import 'package:photopod/services/thumbnail_cache.dart';
import 'package:photopod/utils/formatting.dart';
import 'package:photopod/widgets/media_thumbnail.dart';

/// Describe [item] in a modal dialogue.
///
/// The tiles carry no captions, so this is where the name, the size, the
/// dates and the camera settings live. Everything the Solid server reports is
/// already in hand and appears at once; the details that are inside the photo
/// itself need the file fetched and decoded, so they arrive a moment later.
///
/// [rootPath] is the Pod-relative path of the album root, used to show the
/// folder the way the user navigated to it rather than as the full
/// `photopod/data/...` path.

Future<void> showInfoDialog(
  BuildContext context,
  MediaItem item, {
  String? rootPath,
}) => showDialog<void>(
  context: context,
  builder: (context) => _InfoDialog(item: item, rootPath: rootPath),
);

class _InfoDialog extends StatefulWidget {
  const _InfoDialog({required this.item, this.rootPath});

  final MediaItem item;
  final String? rootPath;

  @override
  State<_InfoDialog> createState() => _InfoDialogState();
}

class _InfoDialogState extends State<_InfoDialog> {
  PhotoMetadata? _metadata;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    if (widget.item.isPhoto) _read();
  }

  Future<void> _read() async {
    setState(() => _reading = true);
    final metadata = await ThumbnailCache.instance.metadata(widget.item);
    if (mounted) {
      setState(() {
        _metadata = metadata;
        _reading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final favourite = context.watch<Favourites>().contains(item);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(item.name, overflow: TextOverflow.ellipsis)),
          if (favourite)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.favorite, color: Color(0xFFE53935), size: 20),
            ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 180,
                    height: 180,
                    child: ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: MediaThumbnail(item: item),
                    ),
                  ),
                ),
              ),
              const Gap(20),
              ..._buildSection(context, 'On your Pod', _podRows()),
              ..._buildPhotoSection(context),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _copy(context),
          icon: const Icon(Icons.copy_all_outlined),
          label: const Text('Copy details'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  // What the Solid server says about the resource.

  List<(String, String)> _podRows() {
    final item = widget.item;
    final root = widget.rootPath;
    final parent = item.parentPath;

    final folder = root == null || !parent.startsWith(root)
        ? parent
        : parent.substring(root.length).replaceFirst('/', '');

    return [
      ('Kind', _kindLabel(item)),
      ('Folder', folder.isEmpty ? 'Album root' : folder),
      if (item.size != null) ('Size', formatBytes(item.size)),
      ('Modified', formatDateTime(item.modified)),
      (
        'Storage',
        item.isEncrypted
            ? 'Encrypted with your security key'
            : 'Plain, unencrypted resource',
      ),
      ('Address', item.url),
    ];
  }

  // What the photo says about itself. Videos carry no EXIF block that
  // PhotoPod can read without decoding the whole file, so they get nothing
  // here rather than an empty heading.

  List<Widget> _buildPhotoSection(BuildContext context) {
    if (!widget.item.isPhoto) return const [];

    if (_reading) {
      return [
        const Gap(20),
        Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const Gap(12),
            Text(
              'Reading the photo...',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ];
    }

    final metadata = _metadata;
    if (metadata == null || metadata.isEmpty) {
      return [
        const Gap(20),
        Text(
          'This photo carries no camera or location information.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }

    final rows = <(String, String)>[
      if (metadata.width != null && metadata.height != null)
        ('Dimensions', _dimensions(metadata)),
      if (metadata.taken != null) ('Taken', formatDateTime(metadata.taken)),
      if (metadata.camera != null) ('Camera', metadata.camera!),
      if (metadata.lens != null) ('Lens', metadata.lens!),
      if (metadata.exposure != null) ('Exposure', metadata.exposure!),
      if (metadata.coordinates != null) ('Location', metadata.coordinates!),
      if (metadata.altitude != null)
        ('Altitude', '${metadata.altitude!.round()} m'),
    ];

    return _buildSection(context, 'In the photo', rows);
  }

  List<Widget> _buildSection(
    BuildContext context,
    String title,
    List<(String, String)> rows,
  ) => [
    Text(title, style: Theme.of(context).textTheme.labelLarge),
    const Gap(8),
    for (final row in rows) _InfoRow(label: row.$1, value: row.$2),
    const Gap(4),
  ];

  Future<void> _copy(BuildContext context) async {
    final metadata = _metadata;
    final lines = [
      widget.item.name,
      for (final row in _podRows()) '${row.$1}: ${row.$2}',
      if (metadata != null && !metadata.isEmpty) ...[
        if (metadata.width != null) 'Dimensions: ${_dimensions(metadata)}',
        if (metadata.taken != null) 'Taken: ${formatDateTime(metadata.taken)}',
        if (metadata.camera != null) 'Camera: ${metadata.camera}',
        if (metadata.lens != null) 'Lens: ${metadata.lens}',
        if (metadata.exposure != null) 'Exposure: ${metadata.exposure}',
        if (metadata.coordinates != null) 'Location: ${metadata.coordinates}',
      ],
    ];

    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Details copied to the clipboard.')),
      );
    }
  }

  static String _dimensions(PhotoMetadata metadata) {
    final width = metadata.width!;
    final height = metadata.height!;
    final megapixels = width * height / 1000000;
    return megapixels >= 0.1
        ? '$width × $height  (${megapixels.toStringAsFixed(1)} MP)'
        : '$width × $height';
  }

  static String _kindLabel(MediaItem item) {
    final extension = extensionOf(item.name).toUpperCase();
    final noun = item.kind?.noun ?? 'file';
    return extension.isEmpty ? noun : '$extension $noun';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}
