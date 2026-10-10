import 'dart:typed_data';

class CameraResponse {
  const CameraResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Uint8List body;
}

abstract interface class CameraTransport {
  Stream<Uint8List> get liveViewChunks;

  Future<CameraResponse> request({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    Uint8List? body,
  });

  Future<void> startLiveView(String path);

  Future<void> stopLiveView();
}

class NativeContractViolation implements Exception {
  const NativeContractViolation(this.field);

  final String field;

  @override
  String toString() => 'nativeContractViolation(field: $field)';
}
