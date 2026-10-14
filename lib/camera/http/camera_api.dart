import 'dart:convert';
import 'dart:typed_data';

import '../gateway/camera_transport.dart';
import '../params/camera_param.dart';
import '../protocol/protocol_profile.dart';
import 'camera_files.dart';

class CameraApiException implements Exception {
  const CameraApiException({
    required this.code,
    required this.path,
    this.statusCode,
    this.cameraCode,
    this.cameraMessage,
  });

  final String code;
  final String path;
  final int? statusCode;
  final String? cameraCode;
  final String? cameraMessage;

  @override
  String toString() => 'CameraApiException('
      'code: $code, path: $path, statusCode: $statusCode, '
      'cameraCode: $cameraCode, cameraMessage: $cameraMessage)';
}

class CameraApi {
  const CameraApi(this._transport);

  static const _jsonHeaders = {'Accept': 'application/json'};

  final CameraTransport _transport;

  Future<Map<String, Object?>> ping() => _requestJson('GET', '/v1/ping');

  Future<Map<String, Object?>> props() => _requestJson('GET', '/v1/props');

  Future<void> startLiveView() => _transport.startLiveView('/v1/liveview');

  Future<void> stopLiveView() => _transport.stopLiveView();

  /// [x] 和 [y] 是实时取景画面中的百分比坐标。
  Future<Map<String, Object?>> focus({required int x, required int y}) {
    RangeError.checkValueInInterval(x, 0, 100, 'x');
    RangeError.checkValueInInterval(y, 0, 100, 'y');
    return _focus(x, y);
  }

  Future<Map<String, Object?>> _focus(int x, int y) async {
    final path = '/v1/lens/focus?pos=$x,$y';
    final response = await _requestJson('POST', path);
    final code = response['errCode'];
    if (code != null && '$code' != '200') {
      throw CameraApiException(
        code: 'cameraError',
        path: _pathOnly(path),
        statusCode: 200,
        cameraCode: '$code',
        cameraMessage: _stringField(response, 'errMsg'),
      );
    }
    return response;
  }

  Future<Map<String, Object?>> shoot({required bool autoFocus}) => _requestJson(
      'POST', '/v1/camera/shoot?af=${autoFocus ? 'camera' : 'off'}');

  Future<Map<String, Object?>> cancelShoot() =>
      _requestJson('POST', '/v1/camera/shoot/cancel');

  Future<Map<String, Object?>> revisions() =>
      _requestJson('GET', '/v1/debug/revisions');

  /// Writes parameters with one of the candidate encodings
  /// (firmware-derived / hardware-unverified).
  ///
  /// A 2xx reply whose `errCode` is present and not 200 is a camera refusal.
  Future<Map<String, Object?>> putParams(
    ParamEndpoint endpoint,
    Map<String, String> values,
    WriteEncoding encoding,
  ) async {
    final path = '/v1/params/${endpoint.name}';
    final json = switch (encoding) {
      WriteEncoding.query => await _requestJson(
          'PUT', Uri(path: path, queryParameters: values).toString()),
      WriteEncoding.form => await _requestJson('PUT', path,
          contentType: 'application/x-www-form-urlencoded',
          body: Uri(queryParameters: values).query),
      WriteEncoding.json => await _requestJson('PUT', path,
          contentType: 'application/json', body: jsonEncode(values)),
      WriteEncoding.unknown => throw ArgumentError.value(encoding, 'encoding'),
    };
    final errCode = json['errCode'];
    if (errCode != null && '$errCode' != '200') {
      throw CameraApiException(
        code: 'cameraError',
        path: path,
        statusCode: 200,
        cameraCode: '$errCode',
        cameraMessage: _stringField(json, 'errMsg'),
      );
    }
    return json;
  }

  Future<List<CameraFile>> photos() async =>
      parsePhotoList(await _requestJson('GET', '/v1/photos'));

  Future<Map<String, Object?>> photoInfo(CameraFile file) =>
      _requestJson('GET', '/v1/photos/${file.dir}/${file.file}/info');

  Future<Uint8List> thumbnail(CameraFile file) async {
    final path = '/v1/photos/${file.dir}/${file.file}?size=thumb';
    final response = await _transport.request(method: 'GET', path: path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CameraApiException(
        code: 'httpStatus',
        path: _pathOnly(path),
        statusCode: response.statusCode,
      );
    }
    return response.body;
  }

  Future<Map<String, Object?>> _requestJson(
    String method,
    String path, {
    String? contentType,
    String? body,
  }) async {
    final response = await _transport.request(
      method: method,
      path: path,
      headers: {
        ..._jsonHeaders,
        if (contentType != null) 'Content-Type': contentType,
      },
      body: body == null ? null : Uint8List.fromList(utf8.encode(body)),
    );
    final json = _decodeObject(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CameraApiException(
        code: 'httpStatus',
        path: _pathOnly(path),
        statusCode: response.statusCode,
        cameraCode: _stringField(json, 'errCode'),
        cameraMessage: _stringField(json, 'errMsg'),
      );
    }
    if (json == null) {
      throw CameraApiException(
        code: 'invalidJson',
        path: _pathOnly(path),
        statusCode: response.statusCode,
      );
    }
    return json;
  }

  Map<String, Object?>? _decodeObject(List<int> body) {
    try {
      final value = jsonDecode(utf8.decode(body));
      return value is Map<String, Object?> ? value : null;
    } on FormatException {
      return null;
    }
  }

  String? _stringField(Map<String, Object?>? json, String key) {
    final value = json?[key];
    return value is String ? value : value?.toString();
  }

  String _pathOnly(String path) => path.split('?').first;
}
