/// TeePod, the trusted image analyser PhotoPod's native builds use.
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

import 'package:flutter/services.dart' show rootBundle;

/// Where TeePod is, and what PhotoPod must see of it before it sends a photo.
///
/// TeePod is a gRPC service running inside a Google Cloud Confidential Space
/// virtual machine, whose memory the host cannot read. It finds faces and
/// tags as the Pod Analyser (`Analyser`) does, but PhotoPod talks to it
/// directly, over mutual TLS, and first has it prove, with an attestation
/// token signed by Google, that it is the expected container image running
/// in such a machine. See lib/services/teepod/.
///
/// Everything but the client certificate is in [configAsset]. The
/// certificate and its key are in [certAsset] and [keyAsset], which are not
/// in git and are bundled only with the native builds: see the README.md
/// beside them.

class TeePodConfig {
  const TeePodConfig({
    required this.host,
    required this.port,
    required this.tlsServerName,
    required this.audience,
    required this.expectedImageDigest,
    required this.allowDebugImage,
    required this.clientCertPem,
    required this.clientKeyPem,
  });

  /// The file holding everything but the client certificate.

  static const String configAsset = 'assets/config/teepod.json';

  /// The client certificate, issued by TeePod's own certificate authority.

  static const String certAsset = 'assets/config/teepod/client-cert.pem';

  /// The client certificate's private key.

  static const String keyAsset = 'assets/config/teepod/client-key.pem';

  /// Name shown in the interface.

  static const String displayName = 'TeePod';

  /// The server's address and gRPC port.

  final String host;
  final int port;

  /// The name in TeePod's certificate, which it makes afresh inside the
  /// enclave each time it starts. Only used as the TLS server name: the
  /// certificate is trusted for its digest, which the attestation vouches
  /// for, not for its name.

  final String tlsServerName;

  /// The audience the attestation token must be issued for.

  final String audience;

  /// The `sha256:...` digest of the container image TeePod must be running.
  /// A redeployed TeePod has a new one, which must be entered here.

  final String expectedImageDigest;

  /// Whether a Confidential Space debug image is accepted. A debug image
  /// lets its operator look inside the running workload, so this must be
  /// false once TeePod runs on a production image.

  final bool allowDebugImage;

  /// The client certificate and its key, PEM encoded.

  final List<int> clientCertPem;
  final List<int> clientKeyPem;

  static Future<TeePodConfig?>? _loaded;

  /// The configuration, read once, or null when this build has no client
  /// certificate, as a web build never does.

  static Future<TeePodConfig?> load() => _loaded ??= _load();

  static Future<TeePodConfig?> _load() async {
    final List<int> cert;
    final List<int> key;
    try {
      cert = (await rootBundle.load(certAsset)).buffer.asUint8List();
      key = (await rootBundle.load(keyAsset)).buffer.asUint8List();
    } on Object {
      return null;
    }
    final json = jsonDecode(await rootBundle.loadString(configAsset));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('$configAsset is not a JSON object');
    }
    return fromJson(json, clientCertPem: cert, clientKeyPem: key);
  }

  /// The configuration in [json], with the certificate and key given.

  static TeePodConfig fromJson(
    Map<String, dynamic> json, {
    required List<int> clientCertPem,
    required List<int> clientKeyPem,
  }) {
    T need<T>(String name) {
      final value = json[name];
      if (value is T) return value;
      throw FormatException('$name is missing from $configAsset');
    }

    final digest = need<String>('expectedImageDigest');
    if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException(
        'expectedImageDigest in $configAsset is not '
        'a sha256: digest',
      );
    }
    return TeePodConfig(
      host: need<String>('host'),
      port: need<int>('port'),
      tlsServerName: need<String>('tlsServerName'),
      audience: need<String>('audience'),
      expectedImageDigest: digest,
      allowDebugImage: json['allowDebugImage'] == true,
      clientCertPem: clientCertPem,
      clientKeyPem: clientKeyPem,
    );
  }
}
