# TeePod protocol

`classifier.proto` is a copy of TeePod's `demo/proto/classifier.proto`, the
gRPC service PhotoPod's native builds use to find faces and tags. The Dart
code in `lib/services/teepod/generated/` is generated from it, and must be
generated again whenever TeePod changes it.

Generating needs `protoc` and the Dart plugin for it:

```bash
dart pub global activate protoc_plugin
```

`protoc` itself comes from Homebrew (`brew install protobuf`), or from
Python's `grpcio-tools`, which ships one (`python -m grpc_tools.protoc`
in place of `protoc` below). The plugin's major version must suit the
`protobuf` package in `pubspec.yaml`: protoc_plugin 25 for protobuf 6.

From the top of the repository:

```bash
cp ../teepod/demo/proto/classifier.proto support/teepod/
protoc --proto_path=support/teepod \
    --dart_out=grpc:lib/services/teepod/generated \
    support/teepod/classifier.proto
```

The generated files are committed, so that building PhotoPod does not need
`protoc`, and are left out of `flutter analyze` (see
`analysis_options.yaml`).
