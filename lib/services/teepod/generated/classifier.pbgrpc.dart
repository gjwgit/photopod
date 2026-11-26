// This is a generated file - do not edit.
//
// Generated from classifier.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'classifier.pb.dart' as $0;

export 'classifier.pb.dart';

@$pb.GrpcServiceName('classifier.v2.ImageAnalyzer')
class ImageAnalyzerClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  ImageAnalyzerClient(super.channel, {super.options, super.interceptors});

  /// Returns a Confidential Space attestation token whose nonces bind
  /// (a) the caller's fresh nonce and (b) the SHA-256 of the server's TLS cert.
  /// A client that verifies this token knows the TLS key lives inside the TEE.
  $grpc.ResponseFuture<$0.AttestResponse> attest(
    $0.AttestRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$attest, request, options: options);
  }

  /// Bidirectional stream: the client sends images as fast as it likes, each
  /// naming the service to run on it; the server returns results as they
  /// complete (possibly out of order; match them with request_id). One stream
  /// may mix both services.
  $grpc.ResponseStream<$0.ImageResult> analyzeStream(
    $async.Stream<$0.ImageRequest> request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$analyzeStream, request, options: options);
  }

  // method descriptors

  static final _$attest =
      $grpc.ClientMethod<$0.AttestRequest, $0.AttestResponse>(
          '/classifier.v2.ImageAnalyzer/Attest',
          ($0.AttestRequest value) => value.writeToBuffer(),
          $0.AttestResponse.fromBuffer);
  static final _$analyzeStream =
      $grpc.ClientMethod<$0.ImageRequest, $0.ImageResult>(
          '/classifier.v2.ImageAnalyzer/AnalyzeStream',
          ($0.ImageRequest value) => value.writeToBuffer(),
          $0.ImageResult.fromBuffer);
}

@$pb.GrpcServiceName('classifier.v2.ImageAnalyzer')
abstract class ImageAnalyzerServiceBase extends $grpc.Service {
  $core.String get $name => 'classifier.v2.ImageAnalyzer';

  ImageAnalyzerServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.AttestRequest, $0.AttestResponse>(
        'Attest',
        attest_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.AttestRequest.fromBuffer(value),
        ($0.AttestResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ImageRequest, $0.ImageResult>(
        'AnalyzeStream',
        analyzeStream,
        true,
        true,
        ($core.List<$core.int> value) => $0.ImageRequest.fromBuffer(value),
        ($0.ImageResult value) => value.writeToBuffer()));
  }

  $async.Future<$0.AttestResponse> attest_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.AttestRequest> $request) async {
    return attest($call, await $request);
  }

  $async.Future<$0.AttestResponse> attest(
      $grpc.ServiceCall call, $0.AttestRequest request);

  $async.Stream<$0.ImageResult> analyzeStream(
      $grpc.ServiceCall call, $async.Stream<$0.ImageRequest> request);
}
