/// What the catalog knows about one photo, video or folder.
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
/// Authors: Graham Williams

library;

import 'package:photopod/models/photo_metadata.dart';
import 'package:photopod/services/media_names.dart' show encodeDate;

/// Where a tag or a face came from when the user put it there. Anything else
/// is the name of the service that suggested it, such as `teepod:vision`.

const String userSource = 'user';

/// A word or phrase describing a photo, such as `beach`.

class PhotoTag {
  /// The tag itself, as shown.

  final String label;

  /// Who added it: [userSource], or the service that suggested it.

  final String source;

  /// How sure a service was, from 0 to 1. The user is always sure.

  final double? confidence;

  const PhotoTag(this.label, {this.source = userSource, this.confidence});

  Map<String, Object> toJson() => {
    'label': label,
    'source': source,
    'confidence': ?confidence,
  };

  /// The tag [toJson] wrote, or null when [json] is not one.

  static PhotoTag? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final label = json['label'];
    if (label is! String || label.isEmpty) return null;
    final source = json['source'];
    final confidence = json['confidence'];
    return PhotoTag(
      label,
      source: source is String && source.isNotEmpty ? source : userSource,
      confidence: confidence is num ? confidence.toDouble() : null,
    );
  }
}

/// A person in a photo, and optionally where they are in it.

class PhotoFace {
  /// Who it is.

  final String name;

  /// Where the face is, as `[left, top, width, height]`, each a fraction of
  /// the photo's width or height, so that the box fits the photo at any
  /// size. Null when only the name is known.

  final List<double>? box;

  /// Who added it: [userSource], or the service that found it.

  final String source;

  const PhotoFace(this.name, {this.box, this.source = userSource});

  Map<String, Object> toJson() => {'name': name, 'box': ?box, 'source': source};

  /// The face [toJson] wrote, or null when [json] is not one. A box that is
  /// not four fractions is dropped and the name kept.

  static PhotoFace? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final box = json['box'];
    final source = json['source'];
    final valid =
        box is List &&
        box.length == 4 &&
        box.every((each) => each is num && each >= 0 && each <= 1);
    return PhotoFace(
      name,
      box: valid ? [for (final each in box) (each as num).toDouble()] : null,
      source: source is String && source.isNotEmpty ? source : userSource,
    );
  }
}

/// A short title for a photo, such as `Sunset over the harbour`, and who
/// gave it: [userSource], or the service that suggested it.

class PhotoTitle {
  final String text;

  final String source;

  const PhotoTitle(this.text, {this.source = userSource});

  /// Whether the user gave this title, rather than a service.

  bool get isUsers => source == userSource;

  Map<String, Object> toJson() => {'text': text, 'source': source};

  /// The title [toJson] wrote, or null when [json] is not one. Plain text is
  /// taken as a title the user gave, which is what a person editing the
  /// catalog by hand would write.

  static PhotoTitle? fromJson(Object? json) {
    if (json is String) {
      return json.trim().isEmpty ? null : PhotoTitle(json.trim());
    }
    if (json is! Map<String, dynamic>) return null;
    final text = json['text'];
    if (text is! String || text.trim().isEmpty) return null;
    final source = json['source'];
    return PhotoTitle(
      text.trim(),
      source: source is String && source.isNotEmpty ? source : userSource,
    );
  }

  /// The title a photo ends up with when [incoming] arrives and it has
  /// [current], or null for none.
  ///
  /// What the user writes always wins: it replaces whatever is there, and
  /// an empty title from the user takes the title away. What a service
  /// suggests is taken only while the user has given no title of their own,
  /// so a later suggestion never overwrites the user's words; an empty
  /// suggestion changes nothing.

  static PhotoTitle? merge(PhotoTitle? current, PhotoTitle incoming) {
    final text = incoming.text.trim();
    if (incoming.isUsers) {
      return text.isEmpty ? null : PhotoTitle(text);
    }
    if (text.isEmpty || (current?.isUsers ?? false)) return current;
    return PhotoTitle(text, source: incoming.source);
  }
}

/// One entry in the catalog: where an item is stored, the name the user
/// knows it by, its title, when it was taken, what its EXIF block says, and
/// the tags and faces the user, or a service, has given it.
///
/// Every field but [path] is optional, since an entry is filled in piece by
/// piece: the name and date when a photo is added, the details once its
/// thumbnail has been read.

class CatalogEntry {
  /// Where the item is stored, relative to the Pod root.

  final String path;

  /// The name the user gave it.

  final String? name;

  /// A short title saying what the photo shows, from the user or a service.

  final PhotoTitle? title;

  /// When it was taken, as ISO 8601 text; see [encodeDate].

  final String? taken;

  /// What the photo's EXIF block says. An empty set of details means the
  /// photo was looked at and says nothing, so it is not looked at again.

  final PhotoMetadata? metadata;

  final List<PhotoTag> tags;

  final List<PhotoFace> faces;

  const CatalogEntry(
    this.path, {
    this.name,
    this.title,
    this.taken,
    this.metadata,
    this.tags = const [],
    this.faces = const [],
  });

  /// The same entry with the given fields replaced.

  CatalogEntry copyWith({
    String? path,
    String? name,
    String? taken,
    PhotoMetadata? metadata,
    List<PhotoTag>? tags,
    List<PhotoFace>? faces,
  }) => CatalogEntry(
    path ?? this.path,
    name: name ?? this.name,
    title: title,
    taken: taken ?? this.taken,
    metadata: metadata ?? this.metadata,
    tags: tags ?? this.tags,
    faces: faces ?? this.faces,
  );

  /// The same entry with [title] in place of its title, or none.

  CatalogEntry withTitle(PhotoTitle? title) => CatalogEntry(
    path,
    name: name,
    title: title,
    taken: taken,
    metadata: metadata,
    tags: tags,
    faces: faces,
  );

  Map<String, Object> toJson() => {
    'path': path,
    'name': ?name,
    'title': ?title?.toJson(),
    'taken': ?taken,
    'exif': ?metadata?.toJson(),
    if (tags.isNotEmpty) 'tags': [for (final tag in tags) tag.toJson()],
    if (faces.isNotEmpty) 'faces': [for (final face in faces) face.toJson()],
  };

  /// The entry [toJson] wrote, or null when [json] has no path. Anything else
  /// that is missing or the wrong shape is left out rather than failing the
  /// whole catalog.

  static CatalogEntry? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final path = json['path'];
    if (path is! String || path.isEmpty) return null;
    final name = json['name'];
    final taken = json['taken'];
    final exif = json['exif'];
    final tags = json['tags'];
    final faces = json['faces'];
    return CatalogEntry(
      path,
      name: name is String && name.isNotEmpty ? name : null,
      title: PhotoTitle.fromJson(json['title']),
      taken: taken is String && DateTime.tryParse(taken) != null ? taken : null,
      metadata: exif is Map<String, dynamic>
          ? PhotoMetadata.fromJson(exif)
          : null,
      tags: [
        if (tags is List)
          for (final each in tags) ?PhotoTag.fromJson(each),
      ],
      faces: [
        if (faces is List)
          for (final each in faces) ?PhotoFace.fromJson(each),
      ],
    );
  }
}
