/// Tests for telling a stored photo that is whole from one cut short.
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

import 'package:flutter_test/flutter_test.dart';

import 'package:photopod/services/media_integrity.dart';

const String _whole =
    '@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n'
    '@prefix solidTerms: <https://solidcommunity.au/predicates/terms#> .\n\n'
    '<https://pod.example/kt/photopod/data/ab.jpg.enc.ttl>\n'
    '    solidTerms:path "photopod/data/ab.jpg.enc.ttl"^^xsd:string ;\n'
    '    solidTerms:iv "mNQLmy431Iv/rczB1ws9VQ=="^^xsd:string ;\n'
    '    solidTerms:encData "8JljNzt1nHNxI359jmPEh7L2"^^xsd:string .\n';

void main() {
  group('isCutShort', () {
    test('is false for a whole encrypted file', () {
      expect(isCutShort(_whole), isFalse);
    });

    test('is true for one that stops inside its encrypted data', () {
      final cut = _whole.substring(0, _whole.indexOf('jmPE'));
      expect(isCutShort(cut), isTrue);
    });

    test('is true for one that stops before its closing full stop', () {
      expect(isCutShort(_whole.substring(0, _whole.lastIndexOf('.'))), isTrue);
    });

    test('is false for anything that is not Turtle', () {
      expect(isCutShort('{"format": "photopod"}\nAAAA'), isFalse);
      expect(isCutShort('AAAABBBB'), isFalse);
    });
  });
}
