/// Ask the user what to do with a photo or video that is already in the Pod.
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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:gap/gap.dart';

import 'package:photopod/dialogs/info_details.dart' show formatDimensions;
import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/utils/formatting.dart';
import 'package:photopod/widgets/media_thumbnail.dart';

/// What the user chose to do with a file that is already in the Pod.

enum DuplicateChoice {
  /// Keep only the copy already in the Pod, with the details of both.
  merge,

  /// Add the new copy all the same, so there are two.
  keepBoth,

  /// Leave the Pod as it is: the new copy is not added and nothing changes.
  skip,
}

/// The user's answer: what to do, and whether to do the same for any further
/// duplicates among the files being added.

typedef DuplicateAnswer = ({DuplicateChoice choice, bool forAll});

/// One row of the comparison: what it is, what the copy in the Pod says,
/// what the new copy says, and what the photo will say once they are merged.

typedef DuplicateRow = ({
  String label,
  String inPod,
  String incoming,
  String merged,
});

/// The rows comparing [inPod], the entry of the copy already in the Pod,
/// with [incoming], the copy being added, and with [merged], the two taken
/// together. Whether the photo in the Pod is a [favourite], and the
/// [albums] it is in, carry over unchanged to the merged photo; the new copy
/// has neither yet.
///
/// A detail neither copy has is left out, so that a photo with no EXIF block
/// is not compared row after empty row.

List<DuplicateRow> duplicateRows(
  CatalogEntry inPod,
  CatalogEntry incoming,
  CatalogEntry merged, {
  bool favourite = false,
  List<String> albums = const [],
}) {
  final rows = <DuplicateRow>[];
  void add(String label, String? Function(CatalogEntry) show) {
    final a = show(inPod) ?? '';
    final b = show(incoming) ?? '';
    if (a.isEmpty && b.isEmpty) return;
    rows.add((label: label, inPod: a, incoming: b, merged: show(merged) ?? ''));
  }

  add('Name', (e) => e.name);
  add('Taken', (e) {
    final when = e.taken == null ? null : DateTime.tryParse(e.taken!);
    return when == null ? null : formatDateTime(when);
  });
  add('Dimensions', (e) {
    final m = e.metadata;
    return m?.width == null || m?.height == null ? null : formatDimensions(m!);
  });
  add('Camera', (e) => e.metadata?.camera);
  add('Lens', (e) => e.metadata?.lens);
  add('Location', (e) {
    final m = e.metadata;
    return m == null || !m.hasLocation
        ? null
        : '${m.latitude!.toStringAsFixed(5)}, '
              '${m.longitude!.toStringAsFixed(5)}';
  });
  add('Title', (e) => e.title?.text);
  add('Place', (e) => e.place?.name);
  add('Tags', (e) => e.tags.map((tag) => tag.label).join(', '));
  add('People', (e) => e.faces.map((face) => face.name).join(', '));

  // The new copy is not in the Pod, so it is in no album and has no heart.

  if (favourite) {
    rows.add((label: 'Favourite', inPod: 'Yes', incoming: '', merged: 'Yes'));
  }
  if (albums.isNotEmpty) {
    final names = albums.join(', ');
    rows.add((label: 'Albums', inPod: names, incoming: '', merged: names));
  }
  return rows;
}

/// Tell the user that [incoming], a file they are adding, is an exact copy
/// of [item], already in their Pod and catalogued as [inPod], and ask
/// whether to merge the two.
///
/// The details of each copy are shown side by side, with what the photo
/// will say once they are merged, and nothing is merged until the user says
/// so. [incomingPicture] is the new copy's thumbnail, when one could be
/// made. When [more] files are still to be added, the user may have the same
/// done for any further duplicates among them. Closing the dialogue without
/// choosing is taken as [DuplicateChoice.skip], which changes nothing.

Future<DuplicateAnswer> showDuplicateDialog(
  BuildContext context, {
  required MediaItem item,
  required CatalogEntry inPod,
  required CatalogEntry incoming,
  Uint8List? incomingPicture,
  bool favourite = false,
  List<String> albums = const [],
  bool more = false,
}) async {
  final merged = CatalogEntry.merge(inPod, incoming);
  final rows = duplicateRows(
    inPod,
    incoming,
    merged,
    favourite: favourite,
    albums: albums,
  );
  var forAll = false;

  final choice = await showDialog<DuplicateChoice>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        icon: const Icon(Icons.content_copy_outlined),
        title: const Text('Already in your Pod'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '"${incoming.name}" is an exact copy of '
                  '"${item.name}", which is already in your Pod. Merging '
                  'keeps only the photo already in your Pod, and gives it '
                  'the details of both.',
                ),
                const Gap(16),
                _Pictures(item: item, incoming: incomingPicture),
                const Gap(16),
                _Comparison(rows: rows),
                if (more) ...[
                  const Gap(8),
                  CheckboxListTile(
                    value: forAll,
                    onChanged: (value) =>
                        setState(() => forAll = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Do the same for any other duplicates being added',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(DuplicateChoice.skip),
            child: const Text("Don't add"),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(DuplicateChoice.keepBoth),
            child: const Text('Keep both'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(DuplicateChoice.merge),
            child: const Text('Merge'),
          ),
        ],
      ),
    ),
  );
  return (choice: choice ?? DuplicateChoice.skip, forAll: forAll);
}

/// The two copies side by side, as small pictures.

class _Pictures extends StatelessWidget {
  const _Pictures({required this.item, required this.incoming});

  final MediaItem item;
  final Uint8List? incoming;

  static const double _size = 120;

  @override
  Widget build(BuildContext context) {
    final picture = incoming;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _labelled(context, 'In your Pod', MediaThumbnail(item: item)),
        _labelled(
          context,
          'Being added',
          picture == null
              ? const Icon(Icons.image_not_supported_outlined)
              : Image.memory(picture, fit: BoxFit.cover),
        ),
      ],
    );
  }

  Widget _labelled(BuildContext context, String label, Widget picture) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox.square(
              dimension: _size,
              child: Center(child: picture),
            ),
          ),
          const Gap(4),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      );
}

/// The details of each copy, and of the merged photo, as a table. A row
/// where the two copies differ is shown in bold, since that is where the
/// merge has something to decide. The table scrolls sideways where the
/// window is too narrow for it.

class _Comparison extends StatelessWidget {
  const _Comparison({required this.rows});

  final List<DuplicateRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
    );
    final body = theme.textTheme.bodySmall;
    final heading = theme.textTheme.labelLarge;

    Widget cell(String text, TextStyle? style) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: SelectableText(text.isEmpty ? '—' : text, style: style),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(170),
        columnWidths: const {0: FixedColumnWidth(96)},
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          TableRow(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            children: [
              cell('', heading),
              cell('In your Pod', heading),
              cell('Being added', heading),
              cell('After merging', heading),
            ],
          ),
          for (final row in rows)
            TableRow(
              children: [
                cell(row.label, label),
                for (final value in [row.inPod, row.incoming, row.merged])
                  cell(
                    value,
                    row.inPod == row.incoming
                        ? body
                        : body?.copyWith(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
