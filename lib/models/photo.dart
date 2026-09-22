/// PhotoPod - the metadata record for a single photo stored in the Pod.
///
// Time-stamp: <Sunday 2026-08-30 14:14:09 +1000 Graham Williams>
///
/// Copyright (C) 2026, Togaware Pty Ltd
///
/// Licensed under the GNU General Public License, Version 3 (the "License");
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
// this program.  If not, see <https://opensource.org/license/gpl-3-0>.
///
/// Authors: Graham Williams

library;

/// One photo held in the Pod, as recorded in the photo index.
///
/// The image bytes themselves are NOT carried here — they live in their own
/// encrypted resource on the Pod, named by [storedName], and are fetched on
/// demand. This record is what the gallery sorts, filters and searches over,
/// so it is deliberately small: the whole index is read in one go at startup.

class Photo {
  const Photo({
    required this.id,
    required this.name,
    required this.storedName,
    required this.uploadedAt,
    this.caption = '',
    this.albums = const [],
    this.tags = const [],
    this.takenAt,
    this.byteSize = 0,
    this.width,
    this.height,
    this.favourite = false,
  });

  /// Stable unique identifier, generated once at upload.

  final String id;

  /// User-visible name. Seeded from the original filename and editable
  /// afterwards without touching the stored resource.

  final String name;

  /// Filename of the encrypted resource within the photos directory, e.g.
  /// `IMG_1234.jpg.enc.ttl`. The thumbnail uses the same name in the
  /// thumbnails directory, so one field locates both.

  final String storedName;

  /// When the photo was added to the Pod.

  final DateTime uploadedAt;

  /// Free-text note about the photo.

  final String caption;

  /// Albums this photo belongs to. A photo can sit in several albums, and an
  /// album is nothing more than a name shared by a set of photos — there is
  /// no separate album resource to keep in step.

  final List<String> albums;

  /// Free-form tags, used by the gallery search.

  final List<String> tags;

  /// When the photo was taken, where that is known. Null when the original
  /// carried no capture date, in which case the gallery falls back to
  /// [uploadedAt] for ordering.

  final DateTime? takenAt;

  /// Size in bytes of the ORIGINAL image, before base64 encoding and
  /// encryption. This is what the user recognises as the size of the photo.

  final int byteSize;

  /// Pixel dimensions of the original, where the decoder reported them.

  final int? width;
  final int? height;

  /// Marked as a favourite by the user.

  final bool favourite;

  /// The date the gallery orders and groups by: the capture date when known,
  /// otherwise the upload date.

  DateTime get effectiveDate => takenAt ?? uploadedAt;

  /// True when [query] matches the name, caption, albums or tags. The query
  /// is expected to be already lower-cased by the caller.

  bool matches(String query) {
    if (query.isEmpty) return true;
    return name.toLowerCase().contains(query) ||
        caption.toLowerCase().contains(query) ||
        albums.any((a) => a.toLowerCase().contains(query)) ||
        tags.any((t) => t.toLowerCase().contains(query));
  }

  // ── JSON serialisation ────────────────────────────────────────────────────

  factory Photo.fromJson(Map<String, dynamic> json) => Photo(
    id: json['id'] as String,
    name: json['name'] as String,
    storedName: json['storedName'] as String,
    uploadedAt:
        DateTime.tryParse(json['uploadedAt'] as String? ?? '') ??
        DateTime.now(),
    caption: json['caption'] as String? ?? '',
    albums: _stringList(json['albums']),
    tags: _stringList(json['tags']),
    takenAt: DateTime.tryParse(json['takenAt'] as String? ?? ''),
    byteSize: (json['byteSize'] as num?)?.toInt() ?? 0,
    width: (json['width'] as num?)?.toInt(),
    height: (json['height'] as num?)?.toInt(),
    favourite: json['favourite'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'storedName': storedName,
    'uploadedAt': uploadedAt.toIso8601String(),
    if (caption.isNotEmpty) 'caption': caption,
    if (albums.isNotEmpty) 'albums': albums,
    if (tags.isNotEmpty) 'tags': tags,
    if (takenAt != null) 'takenAt': takenAt!.toIso8601String(),
    'byteSize': byteSize,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (favourite) 'favourite': true,
  };

  static List<String> _stringList(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];

  Photo copyWith({
    String? name,
    String? caption,
    List<String>? albums,
    List<String>? tags,
    DateTime? takenAt,
    bool? favourite,
  }) => Photo(
    id: id,
    name: name ?? this.name,
    storedName: storedName,
    uploadedAt: uploadedAt,
    caption: caption ?? this.caption,
    albums: albums ?? this.albums,
    tags: tags ?? this.tags,
    takenAt: takenAt ?? this.takenAt,
    byteSize: byteSize,
    width: width,
    height: height,
    favourite: favourite ?? this.favourite,
  );
}
