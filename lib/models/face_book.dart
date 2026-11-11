/// The faces found in the album and the people they belong to.
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

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:photopod/models/catalog_entry.dart';

/// The cosine similarity at or above which two ArcFace embeddings are taken
/// to be the same person. On the sample photos a person matched themselves
/// at 0.64 to 0.84 and strangers at no more than 0.07; 0.40 leaves room for
/// the same face years apart or turned away, while staying well clear of
/// strangers (InsightFace's own verification thresholds for this model lie
/// between about 0.3 and 0.45).

const double faceMatchThreshold = 0.40;

/// Which models produced the embeddings: InsightFace's buffalo_l, SCRFD-10GF
/// and ArcFace ResNet-50, run by analyser/face_analyser. Embeddings from
/// different models cannot be compared, so a book written with others is
/// started afresh. It must match `MODEL_ID` in the analyser.

const String faceModelId = 'buffalo_l:scrfd-10g+arcface-w600k-r50';

/// The version of the faces file this build writes. Version 1 kept no
/// picture of each face and no link to its photo; its photos are looked at
/// again to fill those in, keeping each face with the person it was under.

const int faceBookVersion = 2;

/// A face as the engine hands it over: where it is, as fractions of the
/// photo's size, how sure the detector is, its unit-length embedding, and a
/// small square JPEG of it.

typedef FoundFace = ({
  List<double> box,
  double score,
  Float32List embedding,
  Uint8List? image,
});

/// One face found in one photo.

class FaceRecord {
  /// Unique within the book: the photo's path and the face's place in it.

  final String id;

  /// The Pod-relative path of the photo the face is in, which is what the
  /// album index knows it by.

  final String path;

  /// The photo's URL, so that the file says on its own which photo each
  /// face came from.

  final String? url;

  /// Where the face is, as fractions of the photo's width and height: left,
  /// top, width, height. Fractions, so that the box fits any rendition.

  final List<double> box;

  /// How sure the detector was that this is a face, from 0 to 1.

  final double score;

  /// The ArcFace embedding, scaled to unit length.

  final Float32List embedding;

  /// A small square JPEG of the face, or null for a face recorded before
  /// these were kept.

  final Uint8List? image;

  /// The [Person.id] the face is filed under.

  String person;

  FaceRecord({
    required this.id,
    required this.path,
    this.url,
    required this.box,
    required this.score,
    required this.embedding,
    this.image,
    required this.person,
  });

  /// How much of the photo the face takes up, used to pick the clearest
  /// face of a person for their portrait.

  double get area => box[2] * box[3];

  Map<String, dynamic> toJson() => {
    'path': path,
    if (url != null) 'url': url,
    'box': [for (final v in box) double.parse(v.toStringAsFixed(4))],
    'score': double.parse(score.toStringAsFixed(3)),
    'embedding': base64Encode(embedding.buffer.asUint8List()),
    if (image != null) 'image': base64Encode(image!),
    'person': person,
  };

  static FaceRecord fromJson(String id, Map<String, dynamic> json) =>
      FaceRecord(
        id: id,
        path: json['path'] as String,
        url: json['url'] as String?,
        box: [for (final v in json['box'] as List) (v as num).toDouble()],
        score: (json['score'] as num).toDouble(),
        embedding: Float32List.view(
          Uint8List.fromList(base64Decode(json['embedding'] as String)).buffer,
        ),
        image: json['image'] == null
            ? null
            : base64Decode(json['image'] as String),
        person: json['person'] as String,
      );
}

/// Someone whose face turns up in the album.

class Person {
  /// Unique within the book, and stable: names hang off it.

  final String id;

  /// What the user called them, or null until they are named.

  String? name;

  /// The running sum of the person's embeddings. Its direction is the
  /// centre of their faces, which is what a new face is compared with.

  final Float64List _sum;

  Person(this.id, {this.name}) : _sum = Float64List(_dimensions);

  void _add(Float32List embedding) {
    for (var i = 0; i < _sum.length; i++) {
      _sum[i] += embedding[i];
    }
  }

  void _remove(Float32List embedding) {
    for (var i = 0; i < _sum.length; i++) {
      _sum[i] -= embedding[i];
    }
  }

  /// The cosine similarity between [embedding] and the centre of this
  /// person's faces.

  double similarity(Float32List embedding) {
    var dot = 0.0;
    var norm = 0.0;
    for (var i = 0; i < _sum.length; i++) {
      dot += _sum[i] * embedding[i];
      norm += _sum[i] * _sum[i];
    }
    return norm == 0 ? 0 : dot / math.sqrt(norm);
  }
}

/// ArcFace embeddings have 512 values.

const int _dimensions = 512;

/// Every face found so far, every person they were filed under, and which
/// photos have been looked at.
///
/// A new face joins the person whose faces it is most like, when that is at
/// least [faceMatchThreshold], and otherwise starts a person of its own. The
/// comparison is with the centre of each person's faces rather than with each
/// face, which keeps one blurred photo from joining two people together.

class FaceBook {
  final Map<String, FaceRecord> faces = {};
  final Map<String, Person> people = {};

  /// The photos already looked at, including those with no face in them, so
  /// that they are not looked at again.

  final Set<String> scanned = {};

  int _nextPerson = 1;

  FaceBook();

  /// Whether [path] has already been looked at.

  bool hasScanned(String path) => scanned.contains(path);

  /// Record that the photo at [path], whose URL is [url], was looked at,
  /// and file each of the faces [found] in it.
  ///
  /// A face that was already recorded in the same place in the photo stays
  /// with the person it was under, so that looking at a photo again never
  /// undoes a name or a merge.

  void addPhoto(String path, List<FoundFace> found, {String? url}) {
    final before = faces.values.where((face) => face.path == path).toList();
    for (final face in before) {
      faces.remove(face.id);
      people[face.person]?._remove(face.embedding);
    }
    scanned.add(path);

    for (var i = 0; i < found.length; i++) {
      final face = found[i];
      final previous = before
          .where((old) => boxOverlap(old.box, face.box) >= sameFaceOverlap)
          .firstOrNull;
      final person =
          people[previous?.person] ?? _closest(face.embedding) ?? _newPerson();
      person._add(face.embedding);
      final id = '$path#$i';
      faces[id] = FaceRecord(
        id: id,
        path: path,
        url: url,
        box: face.box,
        score: face.score,
        embedding: face.embedding,
        image: face.image,
        person: person.id,
      );
    }
    _dropEmpty();
  }

  /// Forget [path] and its faces, and anyone left with no face at all.

  void removePhoto(String path) {
    scanned.remove(path);
    final gone = faces.values.where((face) => face.path == path).toList();
    for (final face in gone) {
      faces.remove(face.id);
      people[face.person]?._remove(face.embedding);
    }
    _dropEmpty();
  }

  /// Forget every photo not in [keep], which is how a deleted photo leaves.
  /// Returns whether anything was forgotten.

  bool retainOnly(Set<String> keep) {
    // Faces are looked at as well as the scanned list: a photo waiting to
    // be looked at again still has its faces from last time.

    final known = {...scanned, for (final face in faces.values) face.path};
    final gone = known.where((path) => !keep.contains(path)).toList();
    gone.forEach(removePhoto);
    return gone.isNotEmpty;
  }

  /// File every face of [from] under [into], and forget [from].

  void merge(String from, String into) {
    final source = people[from];
    final target = people[into];
    if (source == null || target == null || from == into) return;
    for (final face in faces.values.where((face) => face.person == from)) {
      face.person = into;
      target._add(face.embedding);
    }
    target.name ??= source.name;
    people.remove(from);
  }

  // A face with a picture of its own beats any without, then the largest,
  // surest face wins.

  static double _clarity(FaceRecord face) =>
      (face.image == null ? 0 : 1) + face.area * face.score;

  /// The faces filed under [person].

  List<FaceRecord> facesOf(String person) =>
      faces.values.where((face) => face.person == person).toList();

  /// The face that pictures [person] best: the largest, most certain one.

  FaceRecord? portraitOf(String person) {
    FaceRecord? best;
    for (final face in faces.values) {
      if (face.person != person) continue;
      if (best == null || _clarity(face) > _clarity(best)) {
        best = face;
      }
    }
    return best;
  }

  /// The photos the faces of [persons] are in.

  Set<String> photosOf(Iterable<String> persons) {
    final wanted = persons.toSet();
    return {
      for (final face in faces.values)
        if (wanted.contains(face.person)) face.path,
    };
  }

  /// The named people in each photo in [paths], as the catalog lists who is
  /// in a photo, credited to [source]. A photo with no one named is listed
  /// with no one, so that what was said of it before is taken back.

  Map<String, List<PhotoFace>> namedFaces(
    Iterable<String> paths,
    String source,
  ) {
    final found = {for (final path in paths) path: <PhotoFace>[]};
    for (final face in faces.values) {
      final name = people[face.person]?.name;
      if (name == null) continue;
      found[face.path]?.add(PhotoFace(name, box: face.box, source: source));
    }
    return found;
  }

  /// Name the people not yet named after whoever the user has said is in
  /// their photos: [given] lists, by path, the people the user named. A name
  /// counts for a face when its box is where the face is, or, without a box,
  /// when it is the only name given for a photo with only one face. The name
  /// most often given to a person's faces is theirs, unless another is given
  /// as often or someone else already has it. Returns who was named.

  Set<String> nameFrom(Map<String, List<PhotoFace>> given) {
    final taken = {
      for (final person in people.values)
        if (person.name != null) person.name!.toLowerCase(),
    };
    final facesIn = <String, List<FaceRecord>>{};
    for (final face in faces.values) {
      (facesIn[face.path] ??= []).add(face);
    }

    final votes = <String, Map<String, int>>{};
    for (final MapEntry(key: path, value: names) in given.entries) {
      final here = facesIn[path] ?? const [];
      final loose = names.where((name) => name.box == null).toList();
      for (final face in here) {
        final name =
            names
                .where(
                  (name) =>
                      name.box != null &&
                      boxOverlap(name.box!, face.box) >= sameFaceOverlap,
                )
                .firstOrNull
                ?.name ??
            (here.length == 1 && loose.length == 1 ? loose.single.name : null);
        if (name == null) continue;
        final count = votes[face.person] ??= {};
        count[name] = (count[name] ?? 0) + 1;
      }
    }

    final named = <String>{};
    for (final MapEntry(key: id, value: count) in votes.entries) {
      final person = people[id];
      if (person == null || person.name != null) continue;
      final ranked = count.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (ranked.length > 1 && ranked[1].value == ranked.first.value) continue;
      final name = ranked.first.key;
      if (!taken.add(name.toLowerCase())) continue;
      person.name = name;
      named.add(id);
    }
    return named;
  }

  Person? _closest(Float32List embedding) {
    Person? best;
    var bestScore = faceMatchThreshold;
    for (final person in people.values) {
      final score = person.similarity(embedding);
      if (score >= bestScore) {
        best = person;
        bestScore = score;
      }
    }
    return best;
  }

  Person _newPerson() {
    var id = 'p${_nextPerson++}';
    while (people.containsKey(id)) {
      id = 'p${_nextPerson++}';
    }
    return people[id] = Person(id);
  }

  void _dropEmpty() {
    final used = {for (final face in faces.values) face.person};
    people.removeWhere((id, person) => !used.contains(id));
  }

  /// The book as the faces file holds it. Besides what is needed to carry
  /// on, each person lists their portrait face and every photo they are in,
  /// so the file describes the people on its own.

  String toJson() => jsonEncode({
    'format': 'photopod-faces',
    'version': faceBookVersion,
    'model': faceModelId,
    'next': _nextPerson,
    'scanned': scanned.toList(),
    'people': {
      for (final person in people.values)
        person.id: {
          if (person.name != null) 'name': person.name,
          'portrait': portraitOf(person.id)?.id,
          'photos': _photosOf(person.id),
        },
    },
    'faces': {for (final face in faces.values) face.id: face.toJson()},
  });

  List<Map<String, String>> _photosOf(String person) {
    final photos = <String, String?>{};
    for (final face in faces.values) {
      if (face.person == person) photos[face.path] ??= face.url;
    }
    return [
      for (final entry in photos.entries)
        {'path': entry.key, if (entry.value != null) 'url': entry.value!},
    ];
  }

  /// The book [json] holds, or an empty one when it was written by other
  /// models, whose embeddings mean nothing to these.
  ///
  /// A photo whose faces were recorded without a picture of each is marked
  /// as not looked at, so that the next scan fills the pictures in.

  static FaceBook fromJson(String json) {
    final book = FaceBook();
    final data = jsonDecode(json) as Map<String, dynamic>;
    if (data['model'] != faceModelId) return book;

    book._nextPerson = (data['next'] as num?)?.toInt() ?? 1;
    book.scanned.addAll((data['scanned'] as List).cast<String>());
    final people = data['people'] as Map<String, dynamic>;
    for (final entry in people.entries) {
      final name = (entry.value as Map<String, dynamic>)['name'] as String?;
      book.people[entry.key] = Person(entry.key, name: name);
    }
    final faces = data['faces'] as Map<String, dynamic>;
    for (final entry in faces.entries) {
      final face = FaceRecord.fromJson(
        entry.key,
        entry.value as Map<String, dynamic>,
      );
      final person = book.people.putIfAbsent(
        face.person,
        () => Person(face.person),
      );
      person._add(face.embedding);
      book.faces[face.id] = face;
      if (face.image == null) book.scanned.remove(face.path);
    }
    return book;
  }
}
