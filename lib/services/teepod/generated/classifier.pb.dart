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

import 'classifier.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'classifier.pbenum.dart';

class AttestRequest extends $pb.GeneratedMessage {
  factory AttestRequest({
    $core.String? nonce,
  }) {
    final result = AttestRequest._();
    if (nonce != null) result.nonce = nonce;
    return result;
  }

  AttestRequest._();

  factory AttestRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AttestRequest()..mergeFromBuffer(data, registry);
  factory AttestRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AttestRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AttestRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'classifier.v2'),
      createEmptyInstance: AttestRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'nonce')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AttestRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AttestRequest copyWith(void Function(AttestRequest) updates) =>
      super.copyWith((message) => updates(message as AttestRequest))
          as AttestRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AttestRequest() / AttestRequest.new instead')
  static AttestRequest create() => AttestRequest._();
  static $pb.GeneratedMessage $_createMessage() => AttestRequest._();
  @$core.override
  AttestRequest createEmptyInstance() => AttestRequest._();
  @$core.pragma('dart2js:noInline')
  static AttestRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AttestRequest>(
          AttestRequest.$_createMessage);
  static AttestRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get nonce => $_getSZ(0);
  @$pb.TagNumber(1)
  set nonce($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNonce() => $_has(0);
  @$pb.TagNumber(1)
  void clearNonce() => $_clearField(1);
}

class AttestResponse extends $pb.GeneratedMessage {
  factory AttestResponse({
    $core.String? token,
    $core.String? certSha256,
  }) {
    final result = AttestResponse._();
    if (token != null) result.token = token;
    if (certSha256 != null) result.certSha256 = certSha256;
    return result;
  }

  AttestResponse._();

  factory AttestResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AttestResponse()..mergeFromBuffer(data, registry);
  factory AttestResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AttestResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AttestResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'classifier.v2'),
      createEmptyInstance: AttestResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'token')
    ..aOS(2, _omitFieldNames ? '' : 'certSha256')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AttestResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AttestResponse copyWith(void Function(AttestResponse) updates) =>
      super.copyWith((message) => updates(message as AttestResponse))
          as AttestResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AttestResponse() / AttestResponse.new instead')
  static AttestResponse create() => AttestResponse._();
  static $pb.GeneratedMessage $_createMessage() => AttestResponse._();
  @$core.override
  AttestResponse createEmptyInstance() => AttestResponse._();
  @$core.pragma('dart2js:noInline')
  static AttestResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AttestResponse>(
          AttestResponse.$_createMessage);
  static AttestResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get token => $_getSZ(0);
  @$pb.TagNumber(1)
  set token($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearToken() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get certSha256 => $_getSZ(1);
  @$pb.TagNumber(2)
  set certSha256($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCertSha256() => $_has(1);
  @$pb.TagNumber(2)
  void clearCertSha256() => $_clearField(2);
}

class ImageRequest extends $pb.GeneratedMessage {
  factory ImageRequest({
    $core.String? requestId,
    $core.List<$core.int>? image,
    Service? service,
    $core.int? maxFaces,
    $core.int? topK,
    $core.double? minScore,
  }) {
    final result = ImageRequest._();
    if (requestId != null) result.requestId = requestId;
    if (image != null) result.image = image;
    if (service != null) result.service = service;
    if (maxFaces != null) result.maxFaces = maxFaces;
    if (topK != null) result.topK = topK;
    if (minScore != null) result.minScore = minScore;
    return result;
  }

  ImageRequest._();

  factory ImageRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageRequest()..mergeFromBuffer(data, registry);
  factory ImageRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'classifier.v2'),
      createEmptyInstance: ImageRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'image', $pb.PbFieldType.OY)
    ..aE<Service>(3, _omitFieldNames ? '' : 'service',
        enumValues: Service.values)
    ..aI(10, _omitFieldNames ? '' : 'maxFaces')
    ..aI(20, _omitFieldNames ? '' : 'topK')
    ..aD(21, _omitFieldNames ? '' : 'minScore', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageRequest copyWith(void Function(ImageRequest) updates) =>
      super.copyWith((message) => updates(message as ImageRequest))
          as ImageRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ImageRequest() / ImageRequest.new instead')
  static ImageRequest create() => ImageRequest._();
  static $pb.GeneratedMessage $_createMessage() => ImageRequest._();
  @$core.override
  ImageRequest createEmptyInstance() => ImageRequest._();
  @$core.pragma('dart2js:noInline')
  static ImageRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ImageRequest>(
          ImageRequest.$_createMessage);
  static ImageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get image => $_getN(1);
  @$pb.TagNumber(2)
  set image($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasImage() => $_has(1);
  @$pb.TagNumber(2)
  void clearImage() => $_clearField(2);

  @$pb.TagNumber(3)
  Service get service => $_getN(2);
  @$pb.TagNumber(3)
  set service(Service value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasService() => $_has(2);
  @$pb.TagNumber(3)
  void clearService() => $_clearField(3);

  /// FACE_RECOGNITION options
  @$pb.TagNumber(10)
  $core.int get maxFaces => $_getIZ(3);
  @$pb.TagNumber(10)
  set maxFaces($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(10)
  $core.bool hasMaxFaces() => $_has(3);
  @$pb.TagNumber(10)
  void clearMaxFaces() => $_clearField(10);

  /// IMAGE_TAGGING options
  @$pb.TagNumber(20)
  $core.int get topK => $_getIZ(4);
  @$pb.TagNumber(20)
  set topK($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(20)
  $core.bool hasTopK() => $_has(4);
  @$pb.TagNumber(20)
  void clearTopK() => $_clearField(20);

  @$pb.TagNumber(21)
  $core.double get minScore => $_getN(5);
  @$pb.TagNumber(21)
  set minScore($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(21)
  $core.bool hasMinScore() => $_has(5);
  @$pb.TagNumber(21)
  void clearMinScore() => $_clearField(21);
}

class Point extends $pb.GeneratedMessage {
  factory Point({
    $core.double? x,
    $core.double? y,
  }) {
    final result = Point._();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    return result;
  }

  Point._();

  factory Point.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Point()..mergeFromBuffer(data, registry);
  factory Point.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Point()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Point',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'classifier.v2'),
      createEmptyInstance: Point.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'x', fieldType: $pb.PbFieldType.OF)
    ..aD(2, _omitFieldNames ? '' : 'y', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Point clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Point copyWith(void Function(Point) updates) =>
      super.copyWith((message) => updates(message as Point)) as Point;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Point() / Point.new instead')
  static Point create() => Point._();
  static $pb.GeneratedMessage $_createMessage() => Point._();
  @$core.override
  Point createEmptyInstance() => Point._();
  @$core.pragma('dart2js:noInline')
  static Point getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Point>(Point.$_createMessage);
  static Point? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get x => $_getN(0);
  @$pb.TagNumber(1)
  set x($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasX() => $_has(0);
  @$pb.TagNumber(1)
  void clearX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get y => $_getN(1);
  @$pb.TagNumber(2)
  set y($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasY() => $_has(1);
  @$pb.TagNumber(2)
  void clearY() => $_clearField(2);
}

class BoundingBox extends $pb.GeneratedMessage {
  factory BoundingBox({
    $core.double? x1,
    $core.double? y1,
    $core.double? x2,
    $core.double? y2,
  }) {
    final result = BoundingBox._();
    if (x1 != null) result.x1 = x1;
    if (y1 != null) result.y1 = y1;
    if (x2 != null) result.x2 = x2;
    if (y2 != null) result.y2 = y2;
    return result;
  }

  BoundingBox._();

  factory BoundingBox.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BoundingBox()..mergeFromBuffer(data, registry);
  factory BoundingBox.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BoundingBox()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BoundingBox',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'classifier.v2'),
      createEmptyInstance: BoundingBox.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'x1', fieldType: $pb.PbFieldType.OF)
    ..aD(2, _omitFieldNames ? '' : 'y1', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'x2', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'y2', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BoundingBox clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BoundingBox copyWith(void Function(BoundingBox) updates) =>
      super.copyWith((message) => updates(message as BoundingBox))
          as BoundingBox;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use BoundingBox() / BoundingBox.new instead')
  static BoundingBox create() => BoundingBox._();
  static $pb.GeneratedMessage $_createMessage() => BoundingBox._();
  @$core.override
  BoundingBox createEmptyInstance() => BoundingBox._();
  @$core.pragma('dart2js:noInline')
  static BoundingBox getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BoundingBox>(
          BoundingBox.$_createMessage);
  static BoundingBox? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get x1 => $_getN(0);
  @$pb.TagNumber(1)
  set x1($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasX1() => $_has(0);
  @$pb.TagNumber(1)
  void clearX1() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get y1 => $_getN(1);
  @$pb.TagNumber(2)
  set y1($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasY1() => $_has(1);
  @$pb.TagNumber(2)
  void clearY1() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get x2 => $_getN(2);
  @$pb.TagNumber(3)
  set x2($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasX2() => $_has(2);
  @$pb.TagNumber(3)
  void clearX2() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get y2 => $_getN(3);
  @$pb.TagNumber(4)
  set y2($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasY2() => $_has(3);
  @$pb.TagNumber(4)
  void clearY2() => $_clearField(4);
}

class Face extends $pb.GeneratedMessage {
  factory Face({
    BoundingBox? box,
    $core.double? score,
    $core.Iterable<Point>? landmarks,
    $core.Iterable<$core.double>? embedding,
  }) {
    final result = Face._();
    if (box != null) result.box = box;
    if (score != null) result.score = score;
    if (landmarks != null) result.landmarks.addAll(landmarks);
    if (embedding != null) result.embedding.addAll(embedding);
    return result;
  }

  Face._();

  factory Face.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Face()..mergeFromBuffer(data, registry);
  factory Face.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Face()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Face',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'classifier.v2'),
      createEmptyInstance: Face.$_createMessage)
    ..aOM<BoundingBox>(1, _omitFieldNames ? '' : 'box',
        subBuilder: BoundingBox.$_createMessage)
    ..aD(2, _omitFieldNames ? '' : 'score', fieldType: $pb.PbFieldType.OF)
    ..pPM<Point>(3, _omitFieldNames ? '' : 'landmarks',
        subBuilder: Point.$_createMessage)
    ..p<$core.double>(4, _omitFieldNames ? '' : 'embedding', $pb.PbFieldType.KF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Face clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Face copyWith(void Function(Face) updates) =>
      super.copyWith((message) => updates(message as Face)) as Face;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Face() / Face.new instead')
  static Face create() => Face._();
  static $pb.GeneratedMessage $_createMessage() => Face._();
  @$core.override
  Face createEmptyInstance() => Face._();
  @$core.pragma('dart2js:noInline')
  static Face getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Face>(Face.$_createMessage);
  static Face? _defaultInstance;

  @$pb.TagNumber(1)
  BoundingBox get box => $_getN(0);
  @$pb.TagNumber(1)
  set box(BoundingBox value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasBox() => $_has(0);
  @$pb.TagNumber(1)
  void clearBox() => $_clearField(1);
  @$pb.TagNumber(1)
  BoundingBox ensureBox() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.double get score => $_getN(1);
  @$pb.TagNumber(2)
  set score($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasScore() => $_has(1);
  @$pb.TagNumber(2)
  void clearScore() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<Point> get landmarks => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<$core.double> get embedding => $_getList(3);
}

class FaceResult extends $pb.GeneratedMessage {
  factory FaceResult({
    $core.Iterable<Face>? faces,
    $core.int? imageWidth,
    $core.int? imageHeight,
  }) {
    final result = FaceResult._();
    if (faces != null) result.faces.addAll(faces);
    if (imageWidth != null) result.imageWidth = imageWidth;
    if (imageHeight != null) result.imageHeight = imageHeight;
    return result;
  }

  FaceResult._();

  factory FaceResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FaceResult()..mergeFromBuffer(data, registry);
  factory FaceResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FaceResult()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FaceResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'classifier.v2'),
      createEmptyInstance: FaceResult.$_createMessage)
    ..pPM<Face>(1, _omitFieldNames ? '' : 'faces',
        subBuilder: Face.$_createMessage)
    ..aI(2, _omitFieldNames ? '' : 'imageWidth')
    ..aI(3, _omitFieldNames ? '' : 'imageHeight')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FaceResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FaceResult copyWith(void Function(FaceResult) updates) =>
      super.copyWith((message) => updates(message as FaceResult)) as FaceResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FaceResult() / FaceResult.new instead')
  static FaceResult create() => FaceResult._();
  static $pb.GeneratedMessage $_createMessage() => FaceResult._();
  @$core.override
  FaceResult createEmptyInstance() => FaceResult._();
  @$core.pragma('dart2js:noInline')
  static FaceResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FaceResult>(FaceResult.$_createMessage);
  static FaceResult? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Face> get faces => $_getList(0);

  @$pb.TagNumber(2)
  $core.int get imageWidth => $_getIZ(1);
  @$pb.TagNumber(2)
  set imageWidth($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasImageWidth() => $_has(1);
  @$pb.TagNumber(2)
  void clearImageWidth() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get imageHeight => $_getIZ(2);
  @$pb.TagNumber(3)
  set imageHeight($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasImageHeight() => $_has(2);
  @$pb.TagNumber(3)
  void clearImageHeight() => $_clearField(3);
}

class Tag extends $pb.GeneratedMessage {
  factory Tag({
    $core.String? name,
    $core.double? score,
  }) {
    final result = Tag._();
    if (name != null) result.name = name;
    if (score != null) result.score = score;
    return result;
  }

  Tag._();

  factory Tag.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Tag()..mergeFromBuffer(data, registry);
  factory Tag.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Tag()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Tag',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'classifier.v2'),
      createEmptyInstance: Tag.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aD(2, _omitFieldNames ? '' : 'score', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Tag clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Tag copyWith(void Function(Tag) updates) =>
      super.copyWith((message) => updates(message as Tag)) as Tag;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Tag() / Tag.new instead')
  static Tag create() => Tag._();
  static $pb.GeneratedMessage $_createMessage() => Tag._();
  @$core.override
  Tag createEmptyInstance() => Tag._();
  @$core.pragma('dart2js:noInline')
  static Tag getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Tag>(Tag.$_createMessage);
  static Tag? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get score => $_getN(1);
  @$pb.TagNumber(2)
  set score($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasScore() => $_has(1);
  @$pb.TagNumber(2)
  void clearScore() => $_clearField(2);
}

class TagResult extends $pb.GeneratedMessage {
  factory TagResult({
    $core.Iterable<Tag>? tags,
  }) {
    final result = TagResult._();
    if (tags != null) result.tags.addAll(tags);
    return result;
  }

  TagResult._();

  factory TagResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TagResult()..mergeFromBuffer(data, registry);
  factory TagResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TagResult()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TagResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'classifier.v2'),
      createEmptyInstance: TagResult.$_createMessage)
    ..pPM<Tag>(1, _omitFieldNames ? '' : 'tags',
        subBuilder: Tag.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TagResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TagResult copyWith(void Function(TagResult) updates) =>
      super.copyWith((message) => updates(message as TagResult)) as TagResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TagResult() / TagResult.new instead')
  static TagResult create() => TagResult._();
  static $pb.GeneratedMessage $_createMessage() => TagResult._();
  @$core.override
  TagResult createEmptyInstance() => TagResult._();
  @$core.pragma('dart2js:noInline')
  static TagResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TagResult>(TagResult.$_createMessage);
  static TagResult? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Tag> get tags => $_getList(0);
}

enum ImageResult_Result { faces, tags, notSet }

class ImageResult extends $pb.GeneratedMessage {
  factory ImageResult({
    $core.String? requestId,
    Service? service,
    FaceResult? faces,
    TagResult? tags,
    $core.String? error,
  }) {
    final result = ImageResult._();
    if (requestId != null) result.requestId = requestId;
    if (service != null) result.service = service;
    if (faces != null) result.faces = faces;
    if (tags != null) result.tags = tags;
    if (error != null) result.error = error;
    return result;
  }

  ImageResult._();

  factory ImageResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageResult()..mergeFromBuffer(data, registry);
  factory ImageResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageResult()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ImageResult_Result>
      _ImageResult_ResultByTag = {
    3: ImageResult_Result.faces,
    4: ImageResult_Result.tags,
    0: ImageResult_Result.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'classifier.v2'),
      createEmptyInstance: ImageResult.$_createMessage)
    ..oo(0, [3, 4])
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aE<Service>(2, _omitFieldNames ? '' : 'service',
        enumValues: Service.values)
    ..aOM<FaceResult>(3, _omitFieldNames ? '' : 'faces',
        subBuilder: FaceResult.$_createMessage)
    ..aOM<TagResult>(4, _omitFieldNames ? '' : 'tags',
        subBuilder: TagResult.$_createMessage)
    ..aOS(5, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageResult copyWith(void Function(ImageResult) updates) =>
      super.copyWith((message) => updates(message as ImageResult))
          as ImageResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ImageResult() / ImageResult.new instead')
  static ImageResult create() => ImageResult._();
  static $pb.GeneratedMessage $_createMessage() => ImageResult._();
  @$core.override
  ImageResult createEmptyInstance() => ImageResult._();
  @$core.pragma('dart2js:noInline')
  static ImageResult getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ImageResult>(
          ImageResult.$_createMessage);
  static ImageResult? _defaultInstance;

  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  ImageResult_Result whichResult() =>
      _ImageResult_ResultByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearResult() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  Service get service => $_getN(1);
  @$pb.TagNumber(2)
  set service(Service value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasService() => $_has(1);
  @$pb.TagNumber(2)
  void clearService() => $_clearField(2);

  @$pb.TagNumber(3)
  FaceResult get faces => $_getN(2);
  @$pb.TagNumber(3)
  set faces(FaceResult value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFaces() => $_has(2);
  @$pb.TagNumber(3)
  void clearFaces() => $_clearField(3);
  @$pb.TagNumber(3)
  FaceResult ensureFaces() => $_ensure(2);

  @$pb.TagNumber(4)
  TagResult get tags => $_getN(3);
  @$pb.TagNumber(4)
  set tags(TagResult value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasTags() => $_has(3);
  @$pb.TagNumber(4)
  void clearTags() => $_clearField(4);
  @$pb.TagNumber(4)
  TagResult ensureTags() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.String get error => $_getSZ(4);
  @$pb.TagNumber(5)
  set error($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
