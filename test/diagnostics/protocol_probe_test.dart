import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/gateway/fake_camera_model.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/camera/http/camera_api.dart';
import 'package:gremote/camera/protocol/protocol_profile.dart';
import 'package:gremote/diagnostics/protocol_probe.dart';

void main() {
  test('read-only report exposes shapes but redacts sensitive values',
      () async {
    final model = FakeCameraModel()
      ..props['ssid'] = 'MY-PRIVATE-CAMERA'
      ..props['serialNo'] = '12345678';
    final gateways =
        FakeCameraGateways(stepDelay: Duration.zero, camera: model);
    addTearDown(gateways.dispose);

    final report = await ProtocolProbe(
      api: CameraApi(gateways.transport),
      socket: gateways.changes,
      listen: Duration.zero,
    ).run(includeWrite: false);

    expect(report.routes['/v1/ping'], 200);
    expect(report.lists['av'], contains('2.8'));
    expect(report.keyTypes['ssid'], 'string');
    expect(report.webSocket, WsSupport.supported);
    expect(report.writeResults, isNull);
    expect(report.toJson().toString(), isNot(contains('MY-PRIVATE-CAMERA')));
    expect(report.toJson().toString(), isNot(contains('12345678')));
  });

  test('write probe finds the only accepted encoding and keeps xv unchanged',
      () async {
    final model = FakeCameraModel(acceptedContentTypes: {'form'});
    final gateways =
        FakeCameraGateways(stepDelay: Duration.zero, camera: model);
    addTearDown(gateways.dispose);
    final before = model.props['xv'];

    final report = await ProtocolProbe(
      api: CameraApi(gateways.transport),
      socket: gateways.changes,
      listen: Duration.zero,
    ).run(includeWrite: true);

    expect(report.writeResults, {
      WriteEncoding.query: false,
      WriteEncoding.form: true,
      WriteEncoding.json: false,
    });
    expect(model.props['xv'], before);
    expect(report.preferredEncoding, WriteEncoding.form);
  });

  test('missing WebSocket support is reported without throwing', () async {
    final model = FakeCameraModel(webSocket: false);
    final gateways =
        FakeCameraGateways(stepDelay: Duration.zero, camera: model);
    addTearDown(gateways.dispose);

    final report = await ProtocolProbe(
      api: CameraApi(gateways.transport),
      socket: gateways.changes,
      listen: Duration.zero,
    ).run(includeWrite: false);

    expect(report.webSocket, WsSupport.unsupported);
  });
}
