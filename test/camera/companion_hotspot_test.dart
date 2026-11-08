import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/app_presence.dart';
import 'package:gremote/camera/companion/companion_transport.dart';
import 'package:gremote/camera/companion/pairing_store.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/connection/connection_state.dart';
import 'package:gremote/camera/gateway/camera_transport.dart';
import 'package:gremote/camera/model/camera_identity.dart';
import 'package:gremote/camera/model/camera_snapshot.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';

class _Connection extends ConnectionController {
  @override
  CameraConnectionState build() => const ConnectionIdle();

  void change(CameraConnectionState next) => state = next;
}

class _Transport implements CompanionTransport {
  final calls = <Completer<CameraResponse>>[];

  @override
  Future<CameraResponse> request({
    required String method,
    required String path,
    required Map<String, String> headers,
    required Uint8List body,
  }) {
    expect(method, 'GET');
    expect(path, '/m10v/v1/hotspot');
    expect(headers, {'X-M10V-Hotspot': '1'});
    expect(body, isEmpty);
    final response = Completer<CameraResponse>();
    calls.add(response);
    return response.future;
  }
}

const _ready = ConnectionReady(
  snapshot: CameraSnapshot(
    identity: CameraIdentity(model: 'RICOH GR III', firmware: '2.10'),
    battery: CameraBattery(level: 80, acPowered: false),
  ),
  firmwareWarning: false,
  cameraKey: 'test-camera',
);

CameraResponse _pairing() {
  final key = List.generate(32, (i) => i);
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
    'schema': 'm10v.companion-pairing/v1',
    'protocol': 1,
    'model': 'GR III',
    'instanceId': 'ab' * 16,
    'keyId': sha256.convert(key).toString().substring(0, 32),
    'keyHex': key.map((i) => i.toRadixString(16).padLeft(2, '0')).join(),
  })));
  return CameraResponse(statusCode: 200, headers: {}, body: bytes);
}

void main() {
  test('a failed discovery read is retried without reconnecting Wi-Fi', () {
    fakeAsync((clock) {
      final connection = _Connection();
      final transport = _Transport();
      final container = ProviderContainer(overrides: [
        connectionControllerProvider.overrideWith(() => connection),
        companionHotspotTransportProvider.overrideWithValue(transport),
      ]);
      container.listen(effectiveCompanionIdentityProvider, (_, __) {});
      connection.change(_ready);
      clock.elapse(Duration.zero);
      transport.calls.single.completeError(const FormatException('bad read'));
      clock.elapse(const Duration(seconds: 1));
      expect(transport.calls, hasLength(2));
      transport.calls.last.complete(_pairing());
      clock.elapse(Duration.zero);
      expect(container.read(effectiveCompanionIdentityProvider)?.instanceId,
          'ab' * 16);
      container.dispose();
    });
  });

  test('discovery recovers when an unavailable service starts later', () {
    fakeAsync((clock) {
      final connection = _Connection();
      final transport = _Transport();
      final container = ProviderContainer(overrides: [
        connectionControllerProvider.overrideWith(() => connection),
        companionHotspotTransportProvider.overrideWithValue(transport),
      ]);
      container.listen(effectiveCompanionIdentityProvider, (_, __) {});
      connection.change(_ready);
      clock.elapse(Duration.zero);
      transport.calls.single.complete(
          CameraResponse(statusCode: 404, headers: {}, body: Uint8List(0)));
      clock.elapse(Duration.zero);
      expect(container.read(effectiveCompanionIdentityProvider), isNull);
      clock.elapse(const Duration(seconds: 20));
      expect(transport.calls, hasLength(2));
      transport.calls.last.complete(_pairing());
      clock.elapse(Duration.zero);
      expect(container.read(effectiveCompanionIdentityProvider)?.instanceId,
          'ab' * 16);
      container.dispose();
    });
  });

  test('only the current network may complete automatic pairing', () async {
    final connection = _Connection();
    final transport = _Transport();
    final container = ProviderContainer(overrides: [
      connectionControllerProvider.overrideWith(() => connection),
      companionHotspotTransportProvider.overrideWithValue(transport),
    ]);
    addTearDown(container.dispose);
    container.listen(effectiveCompanionIdentityProvider, (_, __) {});
    await container.pump();
    expect(transport.calls, isEmpty);

    connection.change(_ready);
    await container.pump();
    expect(transport.calls, hasLength(1));

    connection.change(const ConnectionIdle());
    await container.pump();
    transport.calls.first.complete(_pairing());
    await container.pump();
    expect(container.read(effectiveCompanionIdentityProvider), isNull);

    connection.change(_ready);
    await container.pump();
    expect(transport.calls, hasLength(2));
    final linked = Completer<void>();
    final subscription =
        container.listen(effectiveCompanionIdentityProvider, (_, value) {
      if (value != null && !linked.isCompleted) linked.complete();
    });
    transport.calls.last.complete(_pairing());
    await linked.future.timeout(const Duration(seconds: 2));
    subscription.close();
    expect(container.read(effectiveCompanionIdentityProvider)?.instanceId,
        'ab' * 16);
    expect(container.read(companionPairingIdentityProvider), isNull);
    final identity = container.read(effectiveCompanionIdentityProvider);
    container.read(appForegroundProvider.notifier).state = false;
    await container.pump();
    container.read(appForegroundProvider.notifier).state = true;
    await container.pump();
    expect(container.read(effectiveCompanionIdentityProvider), same(identity));
    expect(transport.calls, hasLength(2));
  });

  test('older services can still use an existing imported pairing', () async {
    final connection = _Connection();
    final transport = _Transport();
    final container = ProviderContainer(overrides: [
      connectionControllerProvider.overrideWith(() => connection),
      companionHotspotTransportProvider.overrideWithValue(transport),
    ]);
    addTearDown(container.dispose);
    const legacy = PairingIdentity(instanceId: 'old', keyId: 'old-key');
    container.read(companionPairingIdentityProvider.notifier).state = legacy;
    container.listen(effectiveCompanionIdentityProvider, (_, __) {});
    connection.change(_ready);
    await container.pump();
    expect(container.read(effectiveCompanionIdentityProvider), isNull);
    transport.calls.single.complete(
        CameraResponse(statusCode: 401, headers: {}, body: Uint8List(0)));
    await container.pump();
    expect(container.read(effectiveCompanionIdentityProvider), same(legacy));
  });
}
