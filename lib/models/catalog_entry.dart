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

import 'dart:math' as math;

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

/// How much two boxes may differ, as [boxOverlap], and still be taken as
/// the same face.

const double sameFaceOverlap = 0.5;

/// How much two boxes, each `[left, top, width, height]`, overlap: the area
/// they share over the area they cover between them, from 0 to 1.

double boxOverlap(List<double> a, List<double> b) {
  final w = math.min(a[0] + a[2], b[0] + b[2]) - math.max(a[0], b[0]);
  final h = math.min(a[1] + a[3], b[1] + b[3]) - math.max(a[1], b[1]);
  if (w <= 0 || h <= 0) return 0;
  final shared = w * h;
  return shared / (a[2] * a[3] + b[2] * b[3] - shared);
}

/// The people in a photo once [source] says it found [found] in it: what
/// [source] found before is replaced, and everyone else's faces stay. A face
/// found under a name already given, or where someone is already named, is
/// left out, so that the user's word stands and no one is listed twice.

List<PhotoFace> withFoundFaces(
  List<PhotoFace> faces,
  String source,
  List<PhotoFace> found,
) {
  final kept = [
    for (final face in faces)
      if (face.source != source) face,
  ];
  bool known(PhotoFace face) => kept.any(
    (other) =>
        other.name.toLowerCase() == face.name.toLowerCase() ||
        (other.box != null &&
            face.box != null &&
            boxOverlap(other.box!, face.box!) >= sameFaceOverlap),
  );
  return [
    ...kept,
    for (final face in found)
      if (!known(face)) face,
  ];
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

/// Where a photo was taken, as the user named it, and the point that name
/// was found at. It stands in for any location in the photo's EXIF block,
/// which is left as the camera wrote it.

class PhotoPlace {
  /// The place as shown, such as `Canberra, Australian Capital Territory`.

  final String name;

  final double latitude;

  final double longitude;

  /// Who gave it: [userSource], or the service that suggested it.

  final String source;

  const PhotoPlace(
    this.name, {
    required this.latitude,
    required this.longitude,
    this.source = userSource,
  });

  Map<String, Object> toJson() => {
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'source': source,
  };

  /// The place [toJson] wrote, or null when [json] is not one.

  static PhotoPlace? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['name'];
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    final source = json['source'];
    if (name is! String || latitude is! num || longitude is! num) return null;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    return PhotoPlace(
      name,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      source: source is String && source.isNotEmpty ? source : userSource,
    );
  }
}

/// One entry in the catalog: where an item is stored, the name the user
/// knows it by, its title, when and where it was taken, what its EXIF block says, and
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

  /// Where it was taken, as the user named it.

  final PhotoPlace? place;

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
    this.place,
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
    place: place,
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
    place: place,
    taken: taken,
    metadata: metadata,
    tags: tags,
    faces: faces,
  );

  /// The same entry with [place] in place of its place, or none.

  CatalogEntry withPlace(PhotoPlace? place) => CatalogEntry(
    path,
    name: name,
    title: title,
    place: place,
    taken: taken,
    metadata: metadata,
    tags: tags,
    faces: faces,
  );

  /// Where the item was taken, as latitude and longitude: the place the user
  /// gave, or else where the photo itself says.

  (double, double)? get location {
    if (place != null) return (place!.latitude, place!.longitude);
    final latitude = metadata?.latitude;
    final longitude = metadata?.longitude;
    return latitude == null || longitude == null ? null : (latitude, longitude);
  }

  Map<String, Object> toJson() => {
    'path': path,
    'name': ?name,
    'title': ?title?.toJson(),
    'place': ?place?.toJson(),
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
      place: PhotoPlace.fromJson(json['place']),
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
