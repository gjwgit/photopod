/// Tests for TeePod: trusting it, and filing what it finds.
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
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:pointycastle/export.dart';

import 'package:photopod/constants/teepod.dart';
import 'package:photopod/services/face_results.dart';
import 'package:photopod/services/tag_results.dart';
import 'package:photopod/services/teepod/attestation.dart';
import 'package:photopod/services/teepod/face_answers.dart';
import 'package:photopod/services/teepod/tag_answers.dart';
import 'package:photopod/services/teepod/teepod_types.dart';

const _nonce = 'aa11';
const _cert = 'bb22';
const _digest =
    'sha256:457c3920e74e9329087a698f78fb5837bf0f5f3340008b513ca2482978cfa999';
const _audience = 'image-classifier-clients';

final _now = DateTime.utc(2026, 11, 23, 12);
final _seconds = _now.millisecondsSinceEpoch ~/ 1000;

Map<String, dynamic> _claims({
  Object? nonces,
  String dbgstat = 'disabled-since-boot',
  List<String> support = const ['LATEST', 'STABLE', 'USABLE'],
  String digest = _digest,
  String hwmodel = 'GCP_AMD_SEV',
}) => {
  'iss': attestationIssuer,
  'aud': _audience,
  'iat': _seconds - 10,
  'nbf': _seconds - 10,
  'exp': _seconds + 3600,
  'eat_nonce': nonces ?? [_nonce, _cert],
  'swname': 'CONFIDENTIAL_SPACE',
  'hwmodel': hwmodel,
  'dbgstat': dbgstat,
  'submods': {
    'confidential_space': {'support_attributes': support},
    'container': {'image_digest': digest},
  },
};

void _check(Map<String, dynamic> claims, {bool allowDebug = false}) =>
    checkWorkloadClaims(
      claims,
      nonce: _nonce,
      certSha256: _cert,
      expectedDigest: _digest,
      allowDebug: allowDebug,
    );

final _refused = throwsA(isA<AttestationError>());

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

String _b64Int(BigInt n) {
  final bytes = <int>[];
  for (var v = n; v > BigInt.zero; v >>= 8) {
    bytes.insert(0, (v & BigInt.from(0xff)).toInt());
  }
  return _b64(bytes);
}

void main() {
  group('the workload', () {
    test('is trusted when every claim is as expected', () {
      expect(() => _check(_claims()), returnsNormally);
    });

    test('must be bound to our nonce and our TLS certificate', () {
      expect(() => _check(_claims(nonces: [_cert])), _refused);
      expect(() => _check(_claims(nonces: [_nonce])), _refused);
      expect(() => _check(_claims(nonces: _nonce)), _refused);
    });

    test('must be the expected container image', () {
      expect(() => _check(_claims(digest: 'sha256:${'0' * 64}')), _refused);
    });

    test('must run on confidential hardware', () {
      expect(() => _check(_claims(hwmodel: 'GCP_SHIELDED_VM')), _refused);
    });

    test('must not be a debug image unless that is allowed', () {
      final debug = _claims(dbgstat: 'enabled', support: const []);
      expect(() => _check(debug), _refused);
      expect(() => _check(debug, allowDebug: true), returnsNormally);
      expect(() => _check(_claims(support: const ['LATEST'])), _refused);
    });
  });

  group('the token', () {
    test('must be from Google, for us, and current', () {
      void valid(Map<String, dynamic> claims) =>
          checkTokenValidity(claims, audience: _audience, now: _now);

      expect(() => valid(_claims()), returnsNormally);
      expect(
        () => valid({
          ..._claims(),
          'aud': [_audience],
        }),
        returnsNormally,
      );
      expect(() => valid({..._claims(), 'iss': 'https://x'}), _refused);
      expect(() => valid({..._claims(), 'aud': 'someone-else'}), _refused);
      expect(() => valid({..._claims(), 'exp': _seconds - 60}), _refused);
      expect(() => valid({..._claims(), 'nbf': _seconds + 60}), _refused);
    });

    // A key pair standing in for Google's, whose public half is served as
    // Google serves its own.

    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          FortunaRandom()..seed(
            KeyParameter(
              Uint8List.fromList(List.generate(32, (i) => i * 7 + 1)),
            ),
          ),
        ),
      );
    final pair = generator.generateKeyPair();
    final public = pair.publicKey;
    final private = pair.privateKey;

    final google = MockClient((request) async {
      if (request.url.path.endsWith('openid-configuration')) {
        return http.Response(
          jsonEncode({'jwks_uri': 'https://www.googleapis.com/keys'}),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'keys': [
            {
              'kty': 'RSA',
              'kid': 'test-key',
              'n': _b64Int(public.modulus!),
              'e': _b64Int(public.exponent!),
            },
          ],
        }),
        200,
      );
    });

    String sign(Map<String, dynamic> claims, {String kid = 'test-key'}) {
      final head = _b64(utf8.encode(jsonEncode({'alg': 'RS256', 'kid': kid})));
      final body = _b64(utf8.encode(jsonEncode(claims)));
      final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
        ..init(true, PrivateKeyParameter<RSAPrivateKey>(private));
      final signature = signer.generateSignature(
        Uint8List.fromList(ascii.encode('$head.$body')),
      );
      return '$head.$body.${_b64(signature.bytes)}';
    }

    Future<Map<String, dynamic>> verify(String token) => verifyAttestationToken(
      token,
      audience: _audience,
      client: google,
      now: _now,
    );

    test('is read once its signature is found good', () async {
      final claims = await verify(sign(_claims()));
      expect(claims['hwmodel'], 'GCP_AMD_SEV');
    });

    test('is refused when altered after signing', () async {
      final parts = sign(_claims()).split('.');
      final forged = _b64(
        utf8.encode(jsonEncode(_claims(digest: 'sha256:${'1' * 64}'))),
      );
      await expectLater(verify('${parts[0]}.$forged.${parts[2]}'), _refused);
    });

    test('is refused when signed with a key Google does not have', () async {
      await expectLater(verify(sign(_claims(), kid: 'other')), _refused);
    });

    test('is refused when it is not a token at all', () async {
      await expectLater(verify('not.a-token'), _refused);
    });
  });

  group('tags', () {
    TeePodTag tag(String name, double score) => (name: name, score: score);

    test('take the Pod Analyser\'s names, and share their phrases\' share', () {
      final tags = chooseTags([
        tag('a person', 0.077),
        tag('a portrait', 0.070),
        tag('a graduation', 0.048),
        tag('clothing', 0.046),
      ]);
      expect(tags.first.tag, 'Portrait');
      expect(tags.first.category, 'People');
      expect(tags.first.score, greaterThan(0.9));
      expect(tags, hasLength(1));
    });

    test('pass over phrases that say too little', () {
      final tags = chooseTags([
        tag('a close-up photo', 0.09),
        tag('a beach', 0.08),
      ]);
      expect(tags.map((t) => t.tag), ['Beach']);
    });

    test('are none when nothing lies close enough', () {
      expect(chooseTags([tag('a musical instrument', 0.024)]), isEmpty);
      expect(chooseTags(const []), isEmpty);
    });

    test('keep at most four, and only those that take enough', () {
      final tags = chooseTags([
        for (final name in ['a dog', 'a cat', 'a bird', 'a horse', 'a fish'])
          tag(name, 0.08),
      ]);
      expect(tags, hasLength(4));
      expect(tags.every((t) => t.score >= minTagShare), isTrue);
    });

    test('a phrase TeePod has gained since is named after itself', () {
      expect(tagForPhrase('a hot air balloon'), (
        tag: 'Hot air balloon',
        category: 'Other',
      ));
    });

    test('are filed as the Pod Analyser\'s are', () {
      final answer = TagResult.parse(
        tagAnswerFromTeePod(
          TeePodAnswer(id: '0', tags: [tag('a waterfall', 0.108)]),
        ),
      );
      expect(answer!.failed, isNull);
      expect(answer.tags.single.tag, 'Waterfall');
      expect(answer.tags.single.category, 'Nature');
    });

    test('a photo TeePod could not read is filed as failed', () {
      final answer = TagResult.parse(
        tagAnswerFromTeePod(const TeePodAnswer(id: '0', error: 'bad image')),
      );
      expect(answer!.failed, 'bad image');
      expect(answer.tags, isEmpty);
    });
  });

  group('faces', () {
    final picture = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 400, height: 200)),
    );
    final embedding = Float32List.fromList(
      List.generate(512, (i) => sin(i.toDouble())),
    );

    TeePodFace face(double score, [double side = 80]) => (
      x1: 100,
      y1: 50,
      x2: 100 + side,
      y2: 50 + side,
      score: score,
      embedding: embedding,
    );

    test('are filed as the Pod Analyser\'s are, each with its picture', () {
      final content = faceAnswerFromTeePod((
        answer: TeePodAnswer(
          id: '0',
          width: 400,
          height: 200,
          faces: [face(0.83), face(0.55), face(0.9, 10)],
        ),
        picture: picture,
      ));
      final answer = FaceResult.parse(content)!;
      expect(answer.failed, isNull);

      // The doubtful face and the tiny one are left out, as by the Pod
      // Analyser.

      final found = answer.faces.single;
      expect(found.box, [0.25, 0.25, 0.2, 0.4]);
      expect(found.score, 0.83);
      expect(found.embedding, hasLength(512));
      final norm = found.embedding.fold<double>(0, (s, v) => s + v * v);
      expect(norm, closeTo(1, 1e-4));
      final thumbnail = img.decodeJpg(found.image!)!;
      expect(thumbnail.width, faceImageSide);
      expect(thumbnail.height, faceImageSide);
    });

    test('a photo TeePod could not read is filed as failed', () {
      final answer = FaceResult.parse(
        faceAnswerFromTeePod((
          answer: const TeePodAnswer(id: '0', error: 'image missing'),
          picture: picture,
        )),
      );
      expect(answer!.failed, 'image missing');
    });
  });

  group('the configuration', () {
    Map<String, dynamic> config() =>
        jsonDecode(
              '{"host": "10.0.0.1", "port": 50051, "tlsServerName": "x", '
              '"audience": "a", "expectedImageDigest": "$_digest"}',
            )
            as Map<String, dynamic>;

    TeePodConfig read(Map<String, dynamic> json) =>
        TeePodConfig.fromJson(json, clientCertPem: [], clientKeyPem: []);

    test('is read, refusing a debug image unless it says otherwise', () {
      expect(read(config()).allowDebugImage, isFalse);
      expect(
        read({...config(), 'allowDebugImage': true}).allowDebugImage,
        true,
      );
    });

    test('must name the image by its digest', () {
      expect(
        () => read({...config(), 'expectedImageDigest': 'latest'}),
        throwsFormatException,
      );
      expect(() => read(config()..remove('host')), throwsFormatException);
    });
  });
}
