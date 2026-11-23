/// TeePod over gRPC, from the native builds.
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
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:grpc/grpc.dart';

import 'package:photopod/constants/teepod.dart';
import 'package:photopod/services/teepod/attestation.dart';
import 'package:photopod/services/teepod/generated/classifier.pbgrpc.dart'
    as pb;
import 'package:photopod/services/teepod/teepod_types.dart';

/// A connection to TeePod that has proved itself, ready for photos.
///
/// TeePod makes its own TLS certificate inside the enclave each time it
/// starts, so no authority can vouch for it. Instead [connect], as TeePod's
/// own client.py does:
///
///  1. reads TeePod's certificate, presenting PhotoPod's client certificate,
///     which TeePod requires of anyone who connects;
///  2. opens a gRPC channel that trusts that certificate and no other, by
///     its SHA-256 digest;
///  3. asks TeePod, over that channel, for an attestation token naming a
///     nonce chosen afresh, and the certificate's digest;
///  4. checks that Google signed the token, that it names both, and that
///     the workload is the expected container image in Confidential Space.
///
/// Only then can photos be sent ([analyse]), over the same pinned channel:
/// whoever holds the private key of the certificate it trusts is the
/// workload Google vouched for, since that key never leaves the enclave.

class TeePod {
  TeePod._(this._channel, this._client);

  final ClientChannel _channel;
  final pb.ImageAnalyzerClient _client;

  /// Whether this platform can reach TeePod at all.

  static const bool isSupported = true;

  /// How long connecting and attesting may take.

  static const Duration _timeout = Duration(seconds: 30);

  /// Connect to TeePod as [config] says, and have it prove itself. Throws
  /// [AttestationError] when it cannot, and closes the connection.

  static Future<TeePod> connect(TeePodConfig config) async {
    final certSha256 = await _serverCertificateDigest(config);
    final channel = ClientChannel(
      config.host,
      port: config.port,
      options: ChannelOptions(
        credentials: _PinnedCredentials(config, certSha256),
        connectTimeout: _timeout,
      ),
    );
    final client = pb.ImageAnalyzerClient(channel);
    try {
      final nonce = _nonce();
      final response = await client.attest(
        pb.AttestRequest(nonce: nonce),
        options: CallOptions(timeout: _timeout),
      );
      final claims = await verifyAttestationToken(
        response.token,
        audience: config.audience,
      );
      checkWorkloadClaims(
        claims,
        nonce: nonce,
        certSha256: certSha256,
        expectedDigest: config.expectedImageDigest,
        allowDebug: config.allowDebugImage,
      );
    } on Object {
      await channel.shutdown();
      rethrow;
    }
    return TeePod._(channel, client);
  }

  /// Have TeePod do [service] for each of [images], as they come, returning
  /// each answer as it is ready, which need not be in the order asked.
  ///
  /// Faces are asked for without limit (TeePod stops at 50, the largest
  /// first). For tags, every one of TeePod's vocabulary that might matter
  /// is asked for, with its score, so that PhotoPod can weigh them against
  /// each other: see tag_answers.dart.

  Stream<TeePodAnswer> analyse(
    Stream<TeePodImage> images,
    TeePodService service,
  ) {
    final requests = images.map(
      (image) => pb.ImageRequest(
        requestId: image.id,
        image: image.image,
        service: switch (service) {
          TeePodService.faces => pb.Service.FACE_RECOGNITION,
          TeePodService.tags => pb.Service.IMAGE_TAGGING,
        },
        maxFaces: 0,
        topK: service == TeePodService.tags ? 50 : null,
      ),
    );
    return _client.analyzeStream(requests).map(_answer);
  }

  /// End the connection, cancelling whatever is under way.

  Future<void> close() => _channel.terminate();

  static TeePodAnswer _answer(pb.ImageResult result) {
    if (result.error.isNotEmpty) {
      return TeePodAnswer(id: result.requestId, error: result.error);
    }
    final faces = result.faces;
    return TeePodAnswer(
      id: result.requestId,
      width: faces.imageWidth,
      height: faces.imageHeight,
      faces: [
        for (final face in faces.faces)
          (
            x1: face.box.x1,
            y1: face.box.y1,
            x2: face.box.x2,
            y2: face.box.y2,
            score: face.score,
            embedding: Float32List.fromList(face.embedding),
          ),
      ],
      tags: [
        for (final tag in result.tags.tags) (name: tag.name, score: tag.score),
      ],
    );
  }

  // 32 random bytes, as the 64 lower case hexadecimal digits TeePod expects.

  static String _nonce() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 32; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  // The SHA-256 digest of TeePod's certificate, read over a connection of
  // its own. The certificate is not checked here: it is trusted only once
  // the attestation names this digest. PhotoPod's client certificate is
  // presented, as TeePod requires, which proves PhotoPod holds the key
  // without giving it away, so a server that is not TeePod learns nothing
  // it could use.

  static Future<String> _serverCertificateDigest(TeePodConfig config) async {
    X509Certificate? seen;
    final socket = await SecureSocket.connect(
      config.host,
      config.port,
      context: _clientContext(config),
      supportedProtocols: const ['h2'],
      onBadCertificate: (certificate) {
        seen = certificate;
        return true;
      },
      timeout: _timeout,
    );
    try {
      final certificate = socket.peerCertificate ?? seen;
      if (certificate == null) {
        throw const AttestationError('TeePod presented no certificate');
      }
      return sha256.convert(certificate.der).toString();
    } finally {
      socket.destroy();
    }
  }
}

/// A TLS context that presents PhotoPod's client certificate and trusts no
/// server by default: TeePod's certificate is let through by its digest.

SecurityContext _clientContext(TeePodConfig config) =>
    SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(config.clientCertPem)
      ..usePrivateKeyBytes(config.clientKeyPem)
      ..setAlpnProtocols(const ['h2'], false);

/// gRPC credentials that present PhotoPod's client certificate and accept
/// one server certificate only: the one whose SHA-256 digest is [pinned].
/// Every connection the channel makes, including any it makes again after
/// losing one, is held to it.

class _PinnedCredentials extends ChannelCredentials {
  _PinnedCredentials(this.config, String pinned)
    : super.secure(
        authority: config.tlsServerName,
        onBadCertificate: (certificate, _) =>
            sha256.convert(certificate.der).toString() == pinned,
      );

  final TeePodConfig config;

  @override
  SecurityContext get securityContext => _clientContext(config);
}
