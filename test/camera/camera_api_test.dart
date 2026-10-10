import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/gateway/camera_transport.dart';
import 'package:gremote/camera/http/camera_api.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/camera/params/camera_param.dart';
import 'package:gremote/camera/protocol/protocol_profile.dart';

void main() {
  test('ping uses the stock endpoint and accepts unknown JSON fields',
      () async {
    final transport = _FakeTransport()
      ..responses.add(
        CameraResponse(
          statusCode: 200,
          headers: const {'content-type': 'application/json'},
          body: File('test/fixtures/ping.json').readAsBytesSync(),
        ),
      );
    final api = CameraApi(transport);

    final result = await api.ping();

    expect(result['pong'], isTrue);
    expect(transport.requests.single.method, 'GET');
    expect(transport.requests.single.path, '/v1/ping');
    expect(transport.requests.single.headers['Accept'], 'application/json');
  });

  test('props requires a JSON object response', () async {
    final transport = _FakeTransport()
      ..responses.add(
        CameraResponse(
          statusCode: 200,
          headers: const {},
          body: Uint8List.fromList(utf8.encode('[1,2,3]')),
        ),
      );

    final error = await _capture(() => CameraApi(transport).props());

    expect(error, isA<CameraApiException>());
    expect((error! as CameraApiException).code, 'invalidJson');
  });

  test('shoot encodes the firmware-confirmed af query', () async {
    final transport = _FakeTransport()..responses.add(_jsonResponse(200, {}));

    await CameraApi(transport).shoot(autoFocus: true);

    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/v1/camera/shoot?af=camera');
    expect(request.body, isNull);
  });

  test('focus validates and encodes integer coordinates', () async {
    final transport = _FakeTransport()..responses.add(_jsonResponse(200, {}));
    final api = CameraApi(transport);

    await api.focus(x: 25, y: 75);

    expect(transport.requests.single.path, '/v1/lens/focus?pos=25,75');
    expect(() => api.focus(x: -1, y: 50), throwsArgumentError);
    expect(() => api.focus(x: 50, y: 101), throwsArgumentError);
  });

  test('non-success preserves typed camera error without response bytes',
      () async {
    final transport = _FakeTransport()
      ..responses.add(
        _jsonResponse(409, {
          'errCode': 'cameraBusy',
          'errMsg': 'Camera is busy',
          'privatePayload': 'must-not-leak',
        }),
      );

    final error = await _capture(() => CameraApi(transport).ping());

    expect(error, isA<CameraApiException>());
    final apiError = error! as CameraApiException;
    expect(apiError.statusCode, 409);
    expect(apiError.cameraCode, 'cameraBusy');
    expect(apiError.cameraMessage, 'Camera is busy');
    expect(apiError.toString(), isNot(contains('must-not-leak')));
  });

  test('live view delegates only relative stock paths', () async {
    final transport = _FakeTransport();
    final api = CameraApi(transport);

    await api.startLiveView();
    await api.stopLiveView();

    expect(transport.startedLiveViewPath, '/v1/liveview');
    expect(transport.stopLiveViewCalls, 1);
  });

  group('putParams', () {
    test('query encoding puts values in the URL', () async {
      final transport = _FakeTransport()
        ..responses.add(_jsonResponse(200, {'av': '4.0'}));

      final json = await CameraApi(transport).putParams(ParamEndpoint.camera,
          {'av': '4.0', 'WBMode': 'auto'}, WriteEncoding.query);

      final request = transport.requests.single;
      expect(request.method, 'PUT');
      expect(request.path, '/v1/params/camera?av=4.0&WBMode=auto');
      expect(request.body, isNull);
      expect(json['av'], '4.0');
    });

    test('form encoding sends an urlencoded body', () async {
      final transport = _FakeTransport()..responses.add(_jsonResponse(200, {}));

      await CameraApi(transport).putParams(
          ParamEndpoint.lens, {'focusSetting': 'mf'}, WriteEncoding.form);

      final request = transport.requests.single;
      expect(request.path, '/v1/params/lens');
      expect(
          request.headers['Content-Type'], 'application/x-www-form-urlencoded');
      expect(utf8.decode(request.body!), 'focusSetting=mf');
    });

    test('json encoding sends a JSON object', () async {
      final transport = _FakeTransport()..responses.add(_jsonResponse(200, {}));

      await CameraApi(transport)
          .putParams(ParamEndpoint.camera, {'xv': '+0.3'}, WriteEncoding.json);

      final request = transport.requests.single;
      expect(request.headers['Content-Type'], 'application/json');
      expect(jsonDecode(utf8.decode(request.body!)), {'xv': '+0.3'});
    });

    test('errCode other than 200 is a camera refusal', () async {
      final transport = _FakeTransport()
        ..responses.add(_jsonResponse(200, {'errCode': 200}))
        ..responses
            .add(_jsonResponse(200, {'errCode': 400, 'errMsg': 'Bad param'}));
      final api = CameraApi(transport);

      await api.putParams(
          ParamEndpoint.camera, {'av': '2.8'}, WriteEncoding.query);
      final error = await _capture(() => api.putParams(
          ParamEndpoint.camera, {'av': '99'}, WriteEncoding.query));

      expect(error, isA<CameraApiException>());
      final apiError = error! as CameraApiException;
      expect(apiError.code, 'cameraError');
      expect(apiError.cameraCode, '400');
    });

    test('unknown encoding is a programming error', () {
      expect(
        () => CameraApi(_FakeTransport()).putParams(
            ParamEndpoint.camera, {'av': '2.8'}, WriteEncoding.unknown),
        throwsArgumentError,
      );
    });
  });

  test('photos lists every directory and file', () async {
    final transport = _FakeTransport()
      ..responses.add(_jsonResponse(200, {
        'errCode': 200,
        'dirs': [
          {
            'name': '100RICOH',
            'files': ['R0000001.JPG', 'R0000001.DNG'],
          },
          {
            'name': '101RICOH',
            'files': ['R0000002.JPG'],
          },
        ],
      }));

    final files = await CameraApi(transport).photos();

    expect(files.map((f) => f.remoteId), [
      '100RICOH/R0000001.JPG',
      '100RICOH/R0000001.DNG',
      '101RICOH/R0000002.JPG',
    ]);
    expect(files.first.baseName, 'R0000001');
  });

  test('thumbnail returns raw bytes', () async {
    final transport = _FakeTransport()
      ..responses.add(CameraResponse(
          statusCode: 200,
          headers: const {},
          body: Uint8List.fromList([0xff, 0xd8])));

    final bytes = await CameraApi(transport)
        .thumbnail(const CameraFile(dir: '100RICOH', file: 'R0000001.JPG'));

    expect(bytes, [0xff, 0xd8]);
    expect(transport.requests.single.path,
        '/v1/photos/100RICOH/R0000001.JPG?size=thumb');
  });
}

Future<Object?> _capture(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } catch (error) {
    return error;
  }
}

CameraResponse _jsonResponse(int statusCode, Object value) => CameraResponse(
      statusCode: statusCode,
      headers: const {'content-type': 'application/json'},
      body: Uint8List.fromList(utf8.encode(jsonEncode(value))),
    );

class _RequestRecord {
  const _RequestRecord({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> headers;
  final Uint8List? body;
}

class _FakeTransport implements CameraTransport {
  final requests = <_RequestRecord>[];
  final responses = <CameraResponse>[];
  String? startedLiveViewPath;
  int stopLiveViewCalls = 0;

  @override
  Stream<Uint8List> get liveViewChunks => const Stream.empty();

  @override
  Future<CameraResponse> request({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    Uint8List? body,
  }) async {
    requests.add(
      _RequestRecord(method: method, path: path, headers: headers, body: body),
    );
    return responses.removeAt(0);
  }

  @override
  Future<void> startLiveView(String path) async {
    startedLiveViewPath = path;
  }

  @override
  Future<void> stopLiveView() async {
    stopLiveViewCalls++;
  }
}
