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
import 'package:photopod/dialogs/message_dialog.dart';
import 'package:photopod/models/albums.dart';
import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/models/favourites.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/photo_metadata.dart';
import 'package:photopod/services/demo_library.dart';
import 'package:photopod/services/media_catalog.dart';
import 'package:photopod/services/shared_with_me.dart' show webIdLabel;
import 'package:photopod/services/thumbnail_cache.dart';
import 'package:photopod/utils/formatting.dart';
import 'package:photopod/widgets/label_editor.dart';
import 'package:photopod/widgets/media_thumbnail.dart';
import 'package:photopod/widgets/place_editor.dart';
import 'package:photopod/widgets/title_editor.dart';

/// Describe [item] in a modal dialogue.
///
/// The tiles carry no captions, so this is where the name, the size, the
/// dates and the camera settings live. Everything the Solid server reports is
/// already in hand and appears at once; the details that are inside the photo
/// itself come from the catalog, or failing that need the thumbnail fetched
/// and decoded, so they may arrive a moment later.
///
/// It is also where the user titles and tags one of their own photos or
/// videos and names the people in it. Each change is saved to the catalog at
/// once.

Future<void> showInfoDialog(BuildContext context, MediaItem item) =>
    showDialog<void>(
      context: context,
      builder: (context) => _InfoDialog(item: item),
    );

class _InfoDialog extends StatefulWidget {
  const _InfoDialog({required this.item});

  final MediaItem item;

  @override
  State<_InfoDialog> createState() => _InfoDialogState();
}

class _InfoDialogState extends State<_InfoDialog> {
  PhotoMetadata? _metadata;
  bool _reading = false;
  PhotoTitle? _title;
  List<PhotoTag> _tags = const [];
  List<PhotoFace> _faces = const [];
  PhotoPlace? _place;

  /// Whether the item is one of the user's own, and so has a catalog entry
  /// to tag. The samples and what others share are not the user's to label.

  bool get _labellable =>
      !widget.item.isShared && !DemoLibrary.isDemo(widget.item);

  @override
  void initState() {
    super.initState();
    final entry = MediaCatalog.entryOf(widget.item.path);
    _title = MediaCatalog.titleOf(widget.item.path);
    _tags = entry?.tags ?? const [];
    _faces = entry?.faces ?? const [];
    _place = entry?.place;
    if (widget.item.isPhoto) _read();
  }

  Future<void> _read() async {
    final known = MediaCatalog.metadataOf(widget.item.path);
    if (known != null) {
      setState(() => _metadata = known);
      return;
    }
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
              ..._buildSection(
                context,
                item.isShared ? 'Shared with you' : 'On your Pod',
                _podRows(),
              ),
              if (_labellable) ..._buildLabels(context),
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
    final albums = context.read<Albums>();
    final inAlbums = [
      for (final name in albums.names)
        if (albums.contains(name, item)) name,
    ];

    if (DemoLibrary.isDemo(item)) {
      return [
        ('Kind', _kindLabel(item)),
        ('Storage', 'A sample included with PhotoPod, not stored in a Pod'),
      ];
    }

    if (item.isShared) {
      return [
        ('Kind', _kindLabel(item)),
        ('Shared by', '${webIdLabel(item.sharedBy!)} (${item.sharedBy})'),
        (
          'Storage',
          item.isEncrypted
              ? 'Encrypted, with the key shared with you'
              : 'Plain, unencrypted resource',
        ),
        ('Address', item.url),
      ];
    }

    return [
      ('Kind', _kindLabel(item)),
      ('Albums', inAlbums.isEmpty ? 'None' : inAlbums.join(', ')),
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

  // The title, then the tags and the people, each a row of chips with a
  // field to add more. What has been used on other photos is offered while
  // the user types.

  List<Widget> _buildLabels(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return [
      const Gap(16),
      Text('Title', style: style),
      const Gap(8),
      TitleEditor(title: _title, onChanged: _saveTitle),
      const Gap(16),
      Text('Tags', style: style),
      const Gap(8),
      LabelEditor(
        labels: [
          for (final tag in _tags)
            (text: tag.label, source: tag.source, confidence: tag.confidence),
        ],
        suggestions: {
          for (final entry in MediaCatalog.entries)
            for (final tag in entry.tags) tag.label,
        },
        hint: 'Add a tag',
        icon: Icons.sell_outlined,
        onAdd: _addTag,
        onRemove: (index) => _saveTags([..._tags]..removeAt(index)),
      ),
      const Gap(16),
      Text('People', style: style),
      const Gap(8),
      LabelEditor(
        labels: [
          for (final face in _faces)
            (text: face.name, source: face.source, confidence: null),
        ],
        suggestions: {
          for (final entry in MediaCatalog.entries)
            for (final face in entry.faces) face.name,
        },
        hint: 'Add a person',
        icon: Icons.person_add_alt,
        onAdd: _addPerson,
        onRemove: (index) => _saveFaces([..._faces]..removeAt(index)),
      ),
      const Gap(16),
      Text('Place', style: style),
      const Gap(8),
      PlaceEditor(
        place: _place,
        photoLocation: _metadata?.coordinates,
        onChanged: _savePlace,
      ),
      const Gap(20),
    ];
  }

  // A tag already there is not added twice, whatever its case. One a
  // service suggested becomes the user's own, since the user has now said
  // so too.

  Future<void> _addTag(String label) async {
    final at = _tags.indexWhere(
      (tag) => tag.label.toLowerCase() == label.toLowerCase(),
    );
    if (at >= 0 && _tags[at].source == userSource) return;
    await _saveTags(
      at < 0
          ? [..._tags, PhotoTag(label)]
          : ([..._tags]..[at] = PhotoTag(_tags[at].label)),
    );
  }

  // As for a tag, and a person a service found keeps the box it found them
  // in.

  Future<void> _addPerson(String name) async {
    final at = _faces.indexWhere(
      (face) => face.name.toLowerCase() == name.toLowerCase(),
    );
    if (at >= 0 && _faces[at].source == userSource) return;
    await _saveFaces(
      at < 0
          ? [..._faces, PhotoFace(name)]
          : ([..._faces]
              ..[at] = PhotoFace(_faces[at].name, box: _faces[at].box)),
    );
  }

  // The change shows at once, and is taken back if the catalog cannot be
  // saved. Whatever the user writes is theirs, replacing a suggestion.

  Future<void> _saveTitle(String text) async {
    final before = _title;
    final title = PhotoTitle.merge(before, PhotoTitle(text));

    // The field saves what was typed as the dialogue closes, by which time
    // there may be nothing left to show it in.

    if (mounted) setState(() => _title = title);
    try {
      await MediaCatalog.setTitle(widget.item.path, PhotoTitle(text));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _title = before);
      await showErrorDialog(context, 'The title was not saved', '$e');
    }
  }

  Future<void> _saveTags(List<PhotoTag> tags) async {
    final before = _tags;
    setState(() => _tags = tags);
    try {
      await MediaCatalog.setTags(widget.item.path, tags);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _tags = before);
      await showErrorDialog(context, 'The tags were not saved', '$e');
    }
  }

  Future<void> _saveFaces(List<PhotoFace> faces) async {
    final before = _faces;
    setState(() => _faces = faces);
    try {
      await MediaCatalog.setFaces(widget.item.path, faces);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _faces = before);
      await showErrorDialog(context, 'The people were not saved', '$e');
    }
  }

  Future<void> _savePlace(PhotoPlace? place) async {
    final before = _place;
    setState(() => _place = place);
    try {
      await MediaCatalog.setPlace(widget.item.path, place);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _place = before);
      await showErrorDialog(context, 'The place was not saved', '$e');
    }
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
      if (_title != null) 'Title: ${_title!.text}',
      for (final row in _podRows()) '${row.$1}: ${row.$2}',
      if (_tags.isNotEmpty) 'Tags: ${_tags.map((tag) => tag.label).join(', ')}',
      if (_faces.isNotEmpty)
        'People: ${_faces.map((face) => face.name).join(', ')}',
      if (_place != null)
        'Place: ${_place!.name} (${_place!.latitude}, ${_place!.longitude})',
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
