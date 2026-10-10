import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/gateway/ble_gateway.dart';

class _FakeBleGateway implements BleGateway {
  _FakeBleGateway(this.bootstrap);

  final CameraBootstrap bootstrap;

  @override
  Stream<CameraDeviceEvent> get events => const Stream.empty();

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<CameraBootstrap> readBootstrap() async => bootstrap;

  @override
  Future<List<BleDeviceCandidate>> scan(Duration timeout) async => const [];

  @override
  Future<void> setCameraPower(int value) async {}

  @override
  Future<void> setNetworkType(int value) async {}

  @override
  Future<void> writeOperationRequest(Uint8List value) async {}
}

void main() {
  test('camera bootstrap debug text redacts wireless credentials', () async {
    final gateway = _FakeBleGateway(
      const CameraBootstrap(
        model: 'RICOH GR III',
        firmware: '2.10',
        batteryLevel: 80,
        acPowered: false,
        ssid: 'RICOH_GR_1234',
        passphrase: 'secret-passphrase',
      ),
    );

    final bootstrap = await gateway.readBootstrap();
    final debugText = bootstrap.toString();

    expect(bootstrap.model, 'RICOH GR III');
    expect(bootstrap.firmware, '2.10');
    expect(bootstrap.batteryLevel, 80);
    expect(debugText, isNot(contains('RICOH_GR_1234')));
    expect(debugText, isNot(contains('secret-passphrase')));
    expect(debugText, contains('<redacted>'));
  });
}
