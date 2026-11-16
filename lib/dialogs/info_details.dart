/// The details shown in, and copied from, the info dialogue.
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

import 'package:photopod/constants/media.dart';
import 'package:photopod/models/albums.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/photo_metadata.dart';
import 'package:photopod/services/demo_library.dart';
import 'package:photopod/services/shared_with_me.dart' show webIdLabel;
import 'package:photopod/utils/formatting.dart';

/// What the Solid server says about [item], and the [albums] it is in, as
/// label and value pairs.

List<(String, String)> podDetails(MediaItem item, Albums albums) {
  final inAlbums = [
    for (final name in albums.names)
      if (albums.contains(name, item)) name,
  ];

  if (DemoLibrary.isDemo(item)) {
    return [
      ('Kind', kindLabel(item)),
      ('Storage', 'A sample included with PhotoPod, not stored in a Pod'),
    ];
  }

  if (item.isShared) {
    return [
      ('Kind', kindLabel(item)),
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
    ('Kind', kindLabel(item)),
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

/// A heading with [title] and a row for each of [rows].

List<Widget> infoSection(
  BuildContext context,
  String title,
  List<(String, String)> rows,
) => [
  Text(title, style: Theme.of(context).textTheme.labelLarge),
  const Gap(8),
  for (final row in rows) InfoRow(label: row.$1, value: row.$2),
  const Gap(4),
];

/// The width and height of a photo, and its megapixels when there are any
/// to speak of.

String formatDimensions(PhotoMetadata metadata) {
  final width = metadata.width!;
  final height = metadata.height!;
  final megapixels = width * height / 1000000;
  return megapixels >= 0.1
      ? '$width × $height  (${megapixels.toStringAsFixed(1)} MP)'
      : '$width × $height';
}

/// The kind of [item], as "JPG photo".

String kindLabel(MediaItem item) {
  final extension = extensionOf(item.name).toUpperCase();
  final noun = item.kind?.noun ?? 'file';
  return extension.isEmpty ? noun : '$extension $noun';
}

/// One label and its value, which may be selected and copied.

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});

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
