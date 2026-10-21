import 'dart:typed_data';
import '../../platform/device_api.g.dart' as native;
import '../gateway/camera_transport.dart';

abstract interface class CompanionTransport {
  Future<CameraResponse> request(
      {required String method,
      required String path,
      required Map<String, String> headers,
      required Uint8List body});
}

class NativeCompanionTransport implements CompanionTransport {
  NativeCompanionTransport({native.CameraDeviceHostApi? api})
      : _api = api ?? native.CameraDeviceHostApi();
  final native.CameraDeviceHostApi _api;
  @override
  Future<CameraResponse> request(
      {required String method,
      required String path,
      required Map<String, String> headers,
      required Uint8List body}) async {
    final result = await _api.companionRequest(method, path, headers, body);
    if (result.statusCode == null ||
        result.body == null ||
        result.headers == null ||
        result.headers!.entries.any((e) => e.key == null || e.value == null)) {
      throw const NativeContractViolation('companionResponse');
    }
    return CameraResponse(
        statusCode: result.statusCode!,
        headers: {for (final e in result.headers!.entries) e.key!: e.value!},
        body: result.body!);
  }
}
