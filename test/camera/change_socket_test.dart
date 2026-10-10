import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/gateway/ble_gateway.dart';
import 'package:gremote/camera/gateway/change_socket.dart';
import 'package:gremote/camera/gateway/fake_camera_model.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/camera/http/camera_api.dart';
import 'package:gremote/camera/params/camera_param.dart';
import 'package:gremote/camera/protocol/protocol_profile.dart';

void main() {
  test('native changes.* events map to typed socket events', () {
    ChangeSocketEvent? map(String type, Object payload) =>
        changeSocketEventFrom(
            CameraDeviceEvent(type: type, jsonPayload: jsonEncode(payload)));

    expect(map('changes.open', {}), isA<ChangeSocketOpened>());
    expect(
        (map('changes.message', {'text': '{"av":"4.0"}'})
                as ChangeSocketMessage)
            .text,
        '{"av":"4.0"}');
    expect((map('changes.closed', {'code': 1001}) as ChangeSocketClosed).code,
        1001);
    expect((map('changes.failure', {}) as ChangeSocketFailed).status, isNull);
    expect(map('changes.message', {}), isNull);
    expect(map('liveView', {'state': 'ended'}), isNull);
  });

  group('FakeCameraModel', () {
    late FakeCameraGateways gateways;
    late CameraApi api;

    setUp(() {
      gateways = FakeCameraGateways(stepDelay: Duration.zero);
      api = CameraApi(gateways.transport);
    });
    tearDown(() => gateways.dispose());

    test('writes are validated and pushed to an open socket', () async {
      final events = <ChangeSocketEvent>[];
      gateways.changes.events.listen(events.add);
      await gateways.changes.open('/v1/changes');

      await api.putParams(
          ParamEndpoint.camera, {'sv': '400'}, WriteEncoding.form);
      await pumpEventQueue();

      expect(gateways.camera.props['sv'], '400');
      expect(events.first, isA<ChangeSocketOpened>());
      expect((events.last as ChangeSocketMessage).text, '{"sv":"400"}');
      await expectLater(
          api.putParams(
              ParamEndpoint.camera, {'exposureMode': 'P'}, WriteEncoding.form),
          throwsA(isA<CameraApiException>()));
    });

    test('rejected encodings return HTTP 400', () async {
      gateways.camera.acceptedContentTypes = {'json'};
      await expectLater(
          api.putParams(
              ParamEndpoint.camera, {'av': '4.0'}, WriteEncoding.query),
          throwsA(isA<CameraApiException>()));
      await api.putParams(
          ParamEndpoint.camera, {'av': '4.0'}, WriteEncoding.json);
      expect(gateways.camera.props['av'], '4.0');
    });

    test('shooting adds a file with capture info', () async {
      await api.shoot(autoFocus: true);
      final files = await api.photos();
      expect(files.single.file, 'R0000001.JPG');
      final info = await api.photoInfo(files.single);
      expect(info['effect'], 'standard');
      expect(info['datetime'], isA<String>());
      expect((await api.props())['storages'], [
        {'storageId': 'storage0', 'remain': 811},
      ]);
    });

    test('a socket without support fails the handshake', () async {
      final camera = FakeCameraModel(webSocket: false);
      final events = <ChangeSocketEvent>[];
      camera.socketEvents.listen(events.add);
      await camera.openSocket('/v1/changes');
      await pumpEventQueue();
      expect((events.single as ChangeSocketFailed).status, 404);
      camera.dispose();
    });
  });
}
