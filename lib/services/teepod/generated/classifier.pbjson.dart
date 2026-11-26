// This is a generated file - do not edit.
//
// Generated from classifier.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use serviceDescriptor instead')
const Service$json = {
  '1': 'Service',
  '2': [
    {'1': 'SERVICE_UNSPECIFIED', '2': 0},
    {'1': 'FACE_RECOGNITION', '2': 1},
    {'1': 'IMAGE_TAGGING', '2': 2},
  ],
};

/// Descriptor for `Service`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List serviceDescriptor = $convert.base64Decode(
    'CgdTZXJ2aWNlEhcKE1NFUlZJQ0VfVU5TUEVDSUZJRUQQABIUChBGQUNFX1JFQ09HTklUSU9OEA'
    'ESEQoNSU1BR0VfVEFHR0lORxAC');

@$core.Deprecated('Use attestRequestDescriptor instead')
const AttestRequest$json = {
  '1': 'AttestRequest',
  '2': [
    {'1': 'nonce', '3': 1, '4': 1, '5': 9, '10': 'nonce'},
  ],
};

/// Descriptor for `AttestRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List attestRequestDescriptor = $convert
    .base64Decode('Cg1BdHRlc3RSZXF1ZXN0EhQKBW5vbmNlGAEgASgJUgVub25jZQ==');

@$core.Deprecated('Use attestResponseDescriptor instead')
const AttestResponse$json = {
  '1': 'AttestResponse',
  '2': [
    {'1': 'token', '3': 1, '4': 1, '5': 9, '10': 'token'},
    {'1': 'cert_sha256', '3': 2, '4': 1, '5': 9, '10': 'certSha256'},
  ],
};

/// Descriptor for `AttestResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List attestResponseDescriptor = $convert.base64Decode(
    'Cg5BdHRlc3RSZXNwb25zZRIUCgV0b2tlbhgBIAEoCVIFdG9rZW4SHwoLY2VydF9zaGEyNTYYAi'
    'ABKAlSCmNlcnRTaGEyNTY=');

@$core.Deprecated('Use imageRequestDescriptor instead')
const ImageRequest$json = {
  '1': 'ImageRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'image', '3': 2, '4': 1, '5': 12, '10': 'image'},
    {
      '1': 'service',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.classifier.v2.Service',
      '10': 'service'
    },
    {'1': 'max_faces', '3': 10, '4': 1, '5': 5, '10': 'maxFaces'},
    {'1': 'top_k', '3': 20, '4': 1, '5': 5, '10': 'topK'},
    {
      '1': 'min_score',
      '3': 21,
      '4': 1,
      '5': 2,
      '9': 0,
      '10': 'minScore',
      '17': true
    },
  ],
  '8': [
    {'1': '_min_score'},
  ],
};

/// Descriptor for `ImageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imageRequestDescriptor = $convert.base64Decode(
    'CgxJbWFnZVJlcXVlc3QSHQoKcmVxdWVzdF9pZBgBIAEoCVIJcmVxdWVzdElkEhQKBWltYWdlGA'
    'IgASgMUgVpbWFnZRIwCgdzZXJ2aWNlGAMgASgOMhYuY2xhc3NpZmllci52Mi5TZXJ2aWNlUgdz'
    'ZXJ2aWNlEhsKCW1heF9mYWNlcxgKIAEoBVIIbWF4RmFjZXMSEwoFdG9wX2sYFCABKAVSBHRvcE'
    'sSIAoJbWluX3Njb3JlGBUgASgCSABSCG1pblNjb3JliAEBQgwKCl9taW5fc2NvcmU=');

@$core.Deprecated('Use pointDescriptor instead')
const Point$json = {
  '1': 'Point',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 2, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 2, '10': 'y'},
  ],
};

/// Descriptor for `Point`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointDescriptor =
    $convert.base64Decode('CgVQb2ludBIMCgF4GAEgASgCUgF4EgwKAXkYAiABKAJSAXk=');

@$core.Deprecated('Use boundingBoxDescriptor instead')
const BoundingBox$json = {
  '1': 'BoundingBox',
  '2': [
    {'1': 'x1', '3': 1, '4': 1, '5': 2, '10': 'x1'},
    {'1': 'y1', '3': 2, '4': 1, '5': 2, '10': 'y1'},
    {'1': 'x2', '3': 3, '4': 1, '5': 2, '10': 'x2'},
    {'1': 'y2', '3': 4, '4': 1, '5': 2, '10': 'y2'},
  ],
};

/// Descriptor for `BoundingBox`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List boundingBoxDescriptor = $convert.base64Decode(
    'CgtCb3VuZGluZ0JveBIOCgJ4MRgBIAEoAlICeDESDgoCeTEYAiABKAJSAnkxEg4KAngyGAMgAS'
    'gCUgJ4MhIOCgJ5MhgEIAEoAlICeTI=');

@$core.Deprecated('Use faceDescriptor instead')
const Face$json = {
  '1': 'Face',
  '2': [
    {
      '1': 'box',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.classifier.v2.BoundingBox',
      '10': 'box'
    },
    {'1': 'score', '3': 2, '4': 1, '5': 2, '10': 'score'},
    {
      '1': 'landmarks',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.classifier.v2.Point',
      '10': 'landmarks'
    },
    {'1': 'embedding', '3': 4, '4': 3, '5': 2, '10': 'embedding'},
  ],
};

/// Descriptor for `Face`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List faceDescriptor = $convert.base64Decode(
    'CgRGYWNlEiwKA2JveBgBIAEoCzIaLmNsYXNzaWZpZXIudjIuQm91bmRpbmdCb3hSA2JveBIUCg'
    'VzY29yZRgCIAEoAlIFc2NvcmUSMgoJbGFuZG1hcmtzGAMgAygLMhQuY2xhc3NpZmllci52Mi5Q'
    'b2ludFIJbGFuZG1hcmtzEhwKCWVtYmVkZGluZxgEIAMoAlIJZW1iZWRkaW5n');

@$core.Deprecated('Use faceResultDescriptor instead')
const FaceResult$json = {
  '1': 'FaceResult',
  '2': [
    {
      '1': 'faces',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.classifier.v2.Face',
      '10': 'faces'
    },
    {'1': 'image_width', '3': 2, '4': 1, '5': 5, '10': 'imageWidth'},
    {'1': 'image_height', '3': 3, '4': 1, '5': 5, '10': 'imageHeight'},
  ],
};

/// Descriptor for `FaceResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List faceResultDescriptor = $convert.base64Decode(
    'CgpGYWNlUmVzdWx0EikKBWZhY2VzGAEgAygLMhMuY2xhc3NpZmllci52Mi5GYWNlUgVmYWNlcx'
    'IfCgtpbWFnZV93aWR0aBgCIAEoBVIKaW1hZ2VXaWR0aBIhCgxpbWFnZV9oZWlnaHQYAyABKAVS'
    'C2ltYWdlSGVpZ2h0');

@$core.Deprecated('Use tagDescriptor instead')
const Tag$json = {
  '1': 'Tag',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'score', '3': 2, '4': 1, '5': 2, '10': 'score'},
  ],
};

/// Descriptor for `Tag`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tagDescriptor = $convert.base64Decode(
    'CgNUYWcSEgoEbmFtZRgBIAEoCVIEbmFtZRIUCgVzY29yZRgCIAEoAlIFc2NvcmU=');

@$core.Deprecated('Use tagResultDescriptor instead')
const TagResult$json = {
  '1': 'TagResult',
  '2': [
    {
      '1': 'tags',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.classifier.v2.Tag',
      '10': 'tags'
    },
  ],
};

/// Descriptor for `TagResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tagResultDescriptor = $convert.base64Decode(
    'CglUYWdSZXN1bHQSJgoEdGFncxgBIAMoCzISLmNsYXNzaWZpZXIudjIuVGFnUgR0YWdz');

@$core.Deprecated('Use imageResultDescriptor instead')
const ImageResult$json = {
  '1': 'ImageResult',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {
      '1': 'service',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.classifier.v2.Service',
      '10': 'service'
    },
    {
      '1': 'faces',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.classifier.v2.FaceResult',
      '9': 0,
      '10': 'faces'
    },
    {
      '1': 'tags',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.classifier.v2.TagResult',
      '9': 0,
      '10': 'tags'
    },
    {'1': 'error', '3': 5, '4': 1, '5': 9, '10': 'error'},
  ],
  '8': [
    {'1': 'result'},
  ],
};

/// Descriptor for `ImageResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imageResultDescriptor = $convert.base64Decode(
    'CgtJbWFnZVJlc3VsdBIdCgpyZXF1ZXN0X2lkGAEgASgJUglyZXF1ZXN0SWQSMAoHc2VydmljZR'
    'gCIAEoDjIWLmNsYXNzaWZpZXIudjIuU2VydmljZVIHc2VydmljZRIxCgVmYWNlcxgDIAEoCzIZ'
    'LmNsYXNzaWZpZXIudjIuRmFjZVJlc3VsdEgAUgVmYWNlcxIuCgR0YWdzGAQgASgLMhguY2xhc3'
    'NpZmllci52Mi5UYWdSZXN1bHRIAFIEdGFncxIUCgVlcnJvchgFIAEoCVIFZXJyb3JCCAoGcmVz'
    'dWx0');
