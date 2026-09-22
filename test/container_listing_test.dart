/// Tests for reading a Solid container listing.
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

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/services/container_listing.dart';

// A listing in the shape a Community Solid Server returns, with the subject
// on its own line and the predicates continuing beneath it.

const _listing = '''
@prefix dc: <http://purl.org/dc/terms/>.
@prefix ldp: <http://www.w3.org/ns/ldp#>.
@prefix posix: <http://www.w3.org/ns/posix/stat#>.
@prefix xsd: <http://www.w3.org/2001/XMLSchema#>.

<> a ldp:Container, ldp:BasicContainer, ldp:Resource;
    dc:modified "2026-09-01T00:00:00.000Z"^^xsd:dateTime.
<> ldp:contains <beach.jpg>, <clip.mp4>, <holiday/>.
<beach.jpg> a <http://www.w3.org/ns/iana/media-types/image/jpeg#Resource>,
    ldp:Resource;
    posix:mtime 1756684800;
    posix:size 204800;
    dc:modified "2026-09-01T02:00:00.000Z"^^xsd:dateTime.
<clip.mp4> a ldp:Resource;
    posix:mtime 1756771200;
    posix:size 1048576.
<holiday/> a ldp:Container, ldp:BasicContainer, ldp:Resource;
    posix:mtime 1756857600.
''';

// The same folder as a Community Solid Server actually writes it: the type
// triple for each resource is one statement, and its stat triples are a
// second statement about the same subject. Reading each statement as its own
// entry is what made every uploaded file appear twice.

const _splitListing = '''
@prefix dc: <http://purl.org/dc/terms/>.
@prefix ldp: <http://www.w3.org/ns/ldp#>.
@prefix posix: <http://www.w3.org/ns/posix/stat#>.
@prefix xsd: <http://www.w3.org/2001/XMLSchema#>.

<> a ldp:Container, ldp:BasicContainer, ldp:Resource;
    dc:modified "2026-09-22T00:00:00.000Z"^^xsd:dateTime;
    ldp:contains <beach.jpg>, <holiday/>.
<beach.jpg> a <http://www.w3.org/ns/iana/media-types/image/jpeg#Resource>,
    ldp:Resource.
<beach.jpg> posix:mtime 1758499200;
    posix:size 204800;
    dc:modified "2026-09-22T01:00:00.000Z"^^xsd:dateTime.
<holiday/> a ldp:Container, ldp:BasicContainer, ldp:Resource.
<holiday/> posix:mtime 1758499200.
''';

void main() {
  group('parseContainerListing', () {
    final entries = parseContainerListing(_listing);

    test('returns one entry per contained resource', () {
      expect(entries.length, 3);
      expect(
        entries.map((e) => e.rawName),
        containsAll(<String>['beach.jpg', 'clip.mp4', 'holiday/']),
      );
    });

    test('skips the statements about the container itself', () {
      expect(entries.any((e) => e.rawName.isEmpty), isFalse);
    });

    test('marks containers apart from files', () {
      final folder = entries.firstWhere((e) => e.rawName == 'holiday/');
      final file = entries.firstWhere((e) => e.rawName == 'beach.jpg');
      expect(folder.isContainer, isTrue);
      expect(file.isContainer, isFalse);
    });

    test('reads the size the server reports', () {
      expect(entries.firstWhere((e) => e.rawName == 'beach.jpg').size, 204800);
      expect(entries.firstWhere((e) => e.rawName == 'holiday/').size, isNull);
    });

    test('prefers the dcterms date over the posix mtime', () {
      final beach = entries.firstWhere((e) => e.rawName == 'beach.jpg');
      expect(beach.modified?.toUtc(), DateTime.utc(2026, 9, 1, 2));
    });

    test('falls back to the posix mtime when there is no dcterms date', () {
      final clip = entries.firstWhere((e) => e.rawName == 'clip.mp4');
      expect(
        clip.modified?.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1756771200 * 1000, isUtc: true),
      );
    });

    test('copes with an empty body', () {
      expect(parseContainerListing(''), isEmpty);
    });
  });

  group('parseContainerListing across split statements', () {
    final entries = parseContainerListing(_splitListing);

    test('returns each resource once, not once per statement', () {
      expect(entries.length, 2);
      expect(
        entries.where((e) => e.rawName == 'beach.jpg').length,
        1,
        reason: 'a file described by two statements must not be duplicated',
      );
      expect(entries.where((e) => e.rawName == 'holiday/').length, 1);
    });

    test('keeps the container flag from whichever statement carried it', () {
      expect(
        entries.firstWhere((e) => e.rawName == 'holiday/').isContainer,
        isTrue,
      );
      expect(
        entries.firstWhere((e) => e.rawName == 'beach.jpg').isContainer,
        isFalse,
      );
    });

    test('merges the stat triples from the second statement', () {
      final beach = entries.firstWhere((e) => e.rawName == 'beach.jpg');
      expect(beach.size, 204800);
      expect(beach.modified?.toUtc(), DateTime.utc(2026, 9, 22, 1));
    });

    test('does not mistake the container for one of its own entries', () {
      expect(entries.any((e) => e.rawName.isEmpty), isFalse);
    });
  });
}
