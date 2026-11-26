/// Checking that TeePod is what it says it is, before any photo is sent.
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
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

/// Who signs Confidential Space attestation tokens.

const String attestationIssuer = 'https://confidentialcomputing.googleapis.com';

/// The hardware a Confidential Space machine may run on.

const Set<String> allowedHardware = {
  'GCP_AMD_SEV',
  'GCP_AMD_SEV_ES',
  'GCP_INTEL_TDX',
};

/// How far the clocks of PhotoPod's device and Google's may disagree.

const Duration clockLeeway = Duration(seconds: 30);

/// TeePod could not prove that it is the expected workload in a trusted
/// execution environment. Nothing is sent to it.

class AttestationError implements Exception {
  const AttestationError(this.message);

  final String message;

  @override
  String toString() => 'TeePod could not be trusted: $message';
}

/// The claims in [token], a Confidential Space attestation token, once its
/// signature is found to be Google's and its issuer, audience and dates are
/// right. Throws [AttestationError] otherwise.
///
/// The keys are fetched from Google with [client], as the issuer's OpenID
/// configuration lists them.

Future<Map<String, dynamic>> verifyAttestationToken(
  String token, {
  required String audience,
  http.Client? client,
  DateTime? now,
}) async {
  final parts = token.split('.');
  if (parts.length != 3) throw const AttestationError('malformed token');
  final Map<String, dynamic> header;
  final Map<String, dynamic> claims;
  final Uint8List signature;
  try {
    header = _jsonPart(parts[0]);
    claims = _jsonPart(parts[1]);
    signature = _base64Url(parts[2]);
  } on FormatException {
    throw const AttestationError('malformed token');
  }
  if (header['alg'] != 'RS256') {
    throw AttestationError('unexpected signing algorithm ${header['alg']}');
  }

  final http.Client fetcher = client ?? http.Client();
  final RSAPublicKey key;
  try {
    key = await _signingKey(header['kid'], fetcher);
  } finally {
    if (client == null) fetcher.close();
  }
  final verifier = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(false, PublicKeyParameter<RSAPublicKey>(key));
  final signed = Uint8List.fromList(ascii.encode('${parts[0]}.${parts[1]}'));
  bool valid;
  try {
    valid = verifier.verifySignature(signed, RSASignature(signature));
  } on Object {
    valid = false;
  }
  if (!valid) throw const AttestationError('the token is not signed by Google');

  checkTokenValidity(claims, audience: audience, now: now);
  return claims;
}

/// Check the issuer, audience and dates of the token [claims].

void checkTokenValidity(
  Map<String, dynamic> claims, {
  required String audience,
  DateTime? now,
}) {
  if (claims['iss'] != attestationIssuer) {
    throw AttestationError('unexpected issuer ${claims['iss']}');
  }
  final aud = claims['aud'];
  if (!(aud == audience || (aud is List && aud.contains(audience)))) {
    throw AttestationError('token is for another audience ($aud)');
  }
  final seconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  final leeway = clockLeeway.inSeconds;
  final exp = claims['exp'];
  if (exp is! num || seconds > exp + leeway) {
    throw const AttestationError('the token has expired');
  }
  for (final name in ['nbf', 'iat']) {
    final at = claims[name];
    if (at is num && seconds + leeway < at) {
      throw const AttestationError('the token is not valid yet');
    }
  }
}

/// Check what [claims] say about the workload: that the token was made for
/// this connection, [nonce] being the one PhotoPod chose and [certSha256]
/// the digest of the TLS certificate PhotoPod is connected to, and that the
/// workload is [expectedDigest] running in Confidential Space on hardware
/// that keeps its memory private. Unless [allowDebug], the Confidential
/// Space image must be a supported production one, whose operator cannot
/// look inside.

void checkWorkloadClaims(
  Map<String, dynamic> claims, {
  required String nonce,
  required String certSha256,
  required String expectedDigest,
  bool allowDebug = false,
}) {
  final raw = claims['eat_nonce'];
  final nonces = raw is String ? [raw] : (raw is List ? raw : const []);
  if (!nonces.contains(nonce)) {
    throw const AttestationError(
      'the token does not carry our nonce (possible replay)',
    );
  }
  if (!nonces.contains(certSha256)) {
    throw const AttestationError(
      'the token is not bound to the TLS certificate we are connected to',
    );
  }
  if (claims['swname'] != 'CONFIDENTIAL_SPACE') {
    throw const AttestationError('not running on a Confidential Space image');
  }
  if (!allowedHardware.contains(claims['hwmodel'])) {
    throw AttestationError('unexpected hardware ${claims['hwmodel']}');
  }
  final submods = _map(claims['submods']);
  if (!allowDebug) {
    if (claims['dbgstat'] != 'disabled-since-boot') {
      throw const AttestationError('the workload is running on a debug image');
    }
    final support = _map(submods['confidential_space'])['support_attributes'];
    if (support is! List || !support.contains('STABLE')) {
      throw const AttestationError(
        'the Confidential Space image is not a supported STABLE release',
      );
    }
  }
  final digest = _map(submods['container'])['image_digest'];
  if (digest != expectedDigest) {
    throw AttestationError(
      'the container image is $digest, not the expected $expectedDigest',
    );
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

Map<String, dynamic> _jsonPart(String part) {
  final value = jsonDecode(utf8.decode(_base64Url(part)));
  if (value is! Map<String, dynamic>) throw const FormatException();
  return value;
}

Uint8List _base64Url(String text) =>
    base64Url.decode(base64Url.normalize(text));

BigInt _unsigned(Uint8List bytes) =>
    bytes.fold(BigInt.zero, (n, b) => (n << 8) | BigInt.from(b));

// Google's signing keys by key ID, fetched once per run of the app, and again
// when a token names a key not among them, as after Google rotates its keys.

final Map<String, RSAPublicKey> _keys = {};

Future<RSAPublicKey> _signingKey(Object? kid, http.Client client) async {
  if (kid is! String) throw const AttestationError('the token names no key');
  final known = _keys[kid];
  if (known != null) return known;

  try {
    final config = jsonDecode(
      (await _get(
        client,
        '$attestationIssuer/.well-known/openid-configuration',
      )),
    );
    final jwks = jsonDecode(await _get(client, config['jwks_uri'] as String));
    for (final jwk in (jwks['keys'] as List).cast<Map<String, dynamic>>()) {
      if (jwk['kty'] != 'RSA' || jwk['kid'] is! String) continue;
      _keys[jwk['kid'] as String] = RSAPublicKey(
        _unsigned(_base64Url(jwk['n'] as String)),
        _unsigned(_base64Url(jwk['e'] as String)),
      );
    }
  } on AttestationError {
    rethrow;
  } on Object catch (e) {
    throw AttestationError('could not fetch Google\'s signing keys: $e');
  }
  final key = _keys[kid];
  if (key == null) {
    throw const AttestationError('the token is signed with an unknown key');
  }
  return key;
}

Future<String> _get(http.Client client, String url) async {
  final response = await client
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) {
    throw AttestationError('$url answered HTTP ${response.statusCode}');
  }
  return response.body;
}
