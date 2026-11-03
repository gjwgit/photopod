/// Tests for grouping the faces found in the album into people.
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

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/models/face_book.dart';

/// A unit-length embedding pointing mostly along [axis], nudged by [jitter]
/// along the next one, so that two calls with the same axis are one person.

Float32List _face(int axis, [double jitter = 0]) {
  final values = Float32List(128);
  values[axis] = 1;
  values[(axis + 1) % 128] = jitter;
  final norm = math.sqrt(1 + jitter * jitter);
  for (var i = 0; i < values.length; i++) {
    values[i] /= norm;
  }
  return values;
}

FoundFace _found(
  Float32List embedding, {
  double size = 0.2,
  double left = 0.1,
  bool withImage = true,
}) => (
  box: [left, 0.1, size, size],
  score: 0.95,
  embedding: embedding,
  image: withImage ? Uint8List.fromList([0xff, 0xd8, 1, 2]) : null,
);

void main() {
  test('the same face in two photos is one person, a stranger another', () {
    final book = FaceBook()
      ..addPhoto('a.jpg', [_found(_face(0)), _found(_face(10))])
      ..addPhoto('b.jpg', [_found(_face(0, 0.3))]);

    expect(book.people, hasLength(2));
    final alice = book.faces['a.jpg#0']!.person;
    expect(book.faces['b.jpg#0']!.person, alice);
    expect(book.faces['a.jpg#1']!.person, isNot(alice));
    expect(book.facesOf(alice), hasLength(2));
  });

  test('a photo with no faces is still remembered as looked at', () {
    final book = FaceBook()..addPhoto('empty.jpg', const []);
    expect(book.hasScanned('empty.jpg'), isTrue);
    expect(book.people, isEmpty);
  });

  test('forgetting a deleted photo drops anyone only it held', () {
    final book = FaceBook()
      ..addPhoto('a.jpg', [_found(_face(0))])
      ..addPhoto('b.jpg', [_found(_face(10))]);

    expect(book.retainOnly({'a.jpg'}), isTrue);
    expect(book.hasScanned('b.jpg'), isFalse);
    expect(book.people, hasLength(1));
    expect(book.retainOnly({'a.jpg'}), isFalse);
  });

  test('merging keeps the target and takes the name when it has none', () {
    final book = FaceBook()
      ..addPhoto('a.jpg', [_found(_face(0))])
      ..addPhoto('b.jpg', [_found(_face(10))]);
    final from = book.faces['a.jpg#0']!.person;
    final into = book.faces['b.jpg#0']!.person;
    book.people[from]!.name = 'Alice';

    book.merge(from, into);

    expect(book.people.keys, [into]);
    expect(book.people[into]!.name, 'Alice');
    expect(book.facesOf(into), hasLength(2));
  });

  test('the portrait is the largest, surest face', () {
    final book = FaceBook()
      ..addPhoto('far.jpg', [_found(_face(0), size: 0.05)])
      ..addPhoto('near.jpg', [_found(_face(0, 0.2), size: 0.4)]);
    final person = book.faces['far.jpg#0']!.person;
    expect(book.portraitOf(person)!.path, 'near.jpg');
  });

  test('the book survives a round trip through JSON', () {
    final book = FaceBook()
      ..addPhoto('a.jpg', [_found(_face(0)), _found(_face(10))])
      ..addPhoto('none.jpg', const []);
    final alice = book.faces['a.jpg#0']!.person;
    book.people[alice]!.name = 'Alice';

    final copy = FaceBook.fromJson(book.toJson());

    expect(copy.scanned, {'a.jpg', 'none.jpg'});
    expect(copy.people[alice]!.name, 'Alice');
    expect(copy.faces['a.jpg#0']!.embedding, book.faces['a.jpg#0']!.embedding);

    // New faces keep matching the people read back, and new people do not
    // reuse an existing identifier.

    copy.addPhoto('b.jpg', [_found(_face(0, 0.1)), _found(_face(40))]);
    expect(copy.faces['b.jpg#0']!.person, alice);
    expect(copy.people, hasLength(3));
  });

  test('the file lists each person with their portrait and photos', () {
    final book = FaceBook()
      ..addPhoto('a.jpg', [_found(_face(0))], url: 'https://pod/a.jpg')
      ..addPhoto('b.jpg', [_found(_face(0, 0.2))], url: 'https://pod/b.jpg');
    final alice = book.faces['a.jpg#0']!.person;
    book.people[alice]!.name = 'Alice';

    final data = jsonDecode(book.toJson()) as Map<String, dynamic>;
    final person = (data['people'] as Map)[alice] as Map;

    expect(data['version'], faceBookVersion);
    expect(person['name'], 'Alice');
    expect(person['portrait'], isNotNull);
    expect(person['photos'], [
      {'path': 'a.jpg', 'url': 'https://pod/a.jpg'},
      {'path': 'b.jpg', 'url': 'https://pod/b.jpg'},
    ]);
    final face = (data['faces'] as Map)['a.jpg#0'] as Map;
    expect(face['url'], 'https://pod/a.jpg');
    expect(base64Decode(face['image'] as String), [0xff, 0xd8, 1, 2]);
  });

  test('looking at a photo again keeps its faces with their people', () {
    final book = FaceBook()
      ..addPhoto('a.jpg', [_found(_face(0))])
      ..addPhoto('b.jpg', [_found(_face(10))]);
    final alice = book.faces['a.jpg#0']!.person;
    final bob = book.faces['b.jpg#0']!.person;
    book.people[alice]!.name = 'Alice';
    book.merge(bob, alice);

    // Bob's face is now filed under Alice by hand; finding it again in the
    // same place must not move it back, even though it looks like Bob.

    book.addPhoto('b.jpg', [_found(_face(10), left: 0.12)]);
    expect(book.faces['b.jpg#0']!.person, alice);
    expect(book.people[alice]!.name, 'Alice');
  });

  test('a version 1 book keeps its people and is looked at again', () {
    final old = FaceBook()
      ..addPhoto('a.jpg', [_found(_face(0), withImage: false)])
      ..addPhoto('empty.jpg', const []);
    final alice = old.faces['a.jpg#0']!.person;
    old.people[alice]!.name = 'Alice';

    final book = FaceBook.fromJson(old.toJson());
    expect(book.hasScanned('a.jpg'), isFalse);
    expect(book.hasScanned('empty.jpg'), isTrue);

    book.addPhoto('a.jpg', [_found(_face(0, 0.05))], url: 'https://pod/a');
    expect(book.faces['a.jpg#0']!.person, alice);
    expect(book.faces['a.jpg#0']!.image, isNotNull);
    expect(book.people[alice]!.name, 'Alice');
  });

  test('a book written by other models is started afresh', () {
    final json = FaceBook().toJson().replaceAll(faceModelId, 'buffalo_l');
    final book = FaceBook.fromJson(
      json.replaceFirst('"scanned":[]', '"scanned":["a.jpg"]'),
    );
    expect(book.scanned, isEmpty);
  });
}
