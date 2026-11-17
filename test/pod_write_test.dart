/// Tests for writing to the Pod again after a failure that may not recur.
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

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:http/http.dart' as http;
import 'package:solidpod/solidpod.dart'
    show AccessForbiddenException, NotLoggedInException;

import 'package:photopod/services/pod_write.dart';

// What solidpod raises when the server answers a write with a status it does
// not single out, such as the 401 for a DPoP proof sent twice.

final Exception _refused = Exception(
  'Failed to create resource!\nURL: https://pod.example/x.jpg.enc.ttl'
  '\nERROR: ',
);

void main() {
  group('isTransientWriteError', () {
    test('counts a refused write and a dropped connection', () {
      expect(isTransientWriteError(_refused), isTrue);
      expect(
        isTransientWriteError(http.ClientException('Connection reset')),
        isTrue,
      );
      expect(isTransientWriteError(TimeoutException('slow')), isTrue);
    });

    test('passes on what a second attempt cannot mend', () {
      expect(
        isTransientWriteError(AccessForbiddenException('no access')),
        isFalse,
      );
      expect(
        isTransientWriteError(NotLoggedInException('logged out')),
        isFalse,
      );
      expect(
        isTransientWriteError(
          Exception('File "x" already exists and overwrite=false'),
        ),
        isFalse,
      );
    });
  });

  group('retryWrite', () {
    test('tries again after a refused write, tidying up first', () async {
      final attempts = <int>[];
      var tidied = 0;
      await retryWrite(
        (attempt) async {
          attempts.add(attempt);
          if (attempt < 3) throw _refused;
        },
        beforeRetry: () async => tidied++,
        pause: Duration.zero,
      );
      expect(attempts, [1, 2, 3]);
      expect(tidied, 2);
    });

    test('gives up after the last attempt with its error', () async {
      var attempts = 0;
      await expectLater(
        retryWrite((_) async {
          attempts++;
          throw _refused;
        }, pause: Duration.zero),
        throwsA(same(_refused)),
      );
      expect(attempts, writeAttempts);
    });

    test('does not repeat a write that cannot succeed', () async {
      var attempts = 0;
      await expectLater(
        retryWrite((_) async {
          attempts++;
          throw AccessForbiddenException('no access');
        }, pause: Duration.zero),
        throwsA(isA<AccessForbiddenException>()),
      );
      expect(attempts, 1);
    });

    test('goes ahead when tidying up fails', () async {
      final attempts = <int>[];
      await retryWrite(
        (attempt) async {
          attempts.add(attempt);
          if (attempt == 1) throw _refused;
        },
        beforeRetry: () async => throw Exception('key file unreachable'),
        pause: Duration.zero,
      );
      expect(attempts, [1, 2]);
    });
  });
}
