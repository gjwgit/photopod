// This is a generated file - do not edit.
//
// Generated from classifier.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class Service extends $pb.ProtobufEnum {
  static const Service SERVICE_UNSPECIFIED =
      Service._(0, _omitEnumNames ? '' : 'SERVICE_UNSPECIFIED');
  static const Service FACE_RECOGNITION =
      Service._(1, _omitEnumNames ? '' : 'FACE_RECOGNITION');
  static const Service IMAGE_TAGGING =
      Service._(2, _omitEnumNames ? '' : 'IMAGE_TAGGING');

  static const $core.List<Service> values = <Service>[
    SERVICE_UNSPECIFIED,
    FACE_RECOGNITION,
    IMAGE_TAGGING,
  ];

  static final $core.List<Service?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static Service? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Service._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
