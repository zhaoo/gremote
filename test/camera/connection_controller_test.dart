import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/connection/connection_state.dart';
import 'package:gremote/camera/gateway/ble_gateway.dart';
import 'package:gremote/camera/gateway/camera_transport.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/camera/gateway/wifi_gateway.dart';
import 'package:gremote/camera/http/live_view_parser.dart';
import 'package:gremote/diagnostics/diagnostic_store.dart';
import 'package:gremote/platform/camera_permission_gate.dart';

void main() {
  test('connect follows the required gateway order', () async {
    final harness = _Harness();

    await harness.controller.connect();

    expect(
      harness.trace,
      [
        'scan',
        'connectBle',
        'readBootstrap',
        'setCameraPower:1',
        'setNetworkType:1',
        'connectCameraWifi',
        'ping',
        'props',
      ],
    );
    expect(harness.state, isA<ConnectionReady>());
  });

  test('permission denial prevents BLE and Wi-Fi calls', () async {
    final harness = _Harness(
      permissionStatus: CameraPermissionStatus.denied,
    );

    await harness.controller.connect();

    expect(harness.state, isA<ConnectionFailed>());
    expect(harness.trace, isEmpty);
  });

  test('empty scan produces a retryable failure', () async {
    final harness = _Harness()..ble.devices = [];

    await harness.controller.connect();

    final state = harness.state as ConnectionFailed;
    expect(state.failure.code, 'cameraNotFound');
    expect(state.failure.retryable, isTrue);
  });

  test('unsupported model stops before camera power writes', () async {
    final harness = _Harness()
      ..ble.bootstrap = const CameraBootstrap(
        model: 'RICOH GR IV',
        firmware: '1.00',
        batteryLevel: 80,
        acPowered: false,
        ssid: 'RICOH_secret',
        passphrase: 'secret-password',
      );

    await harness.controller.connect();

    final state = harness.state as ConnectionFailed;
    expect(state.failure.code, 'unsupportedCamera');
    expect(harness.trace, isNot(contains('setCameraPower:1')));
    expect(state.toString(), isNot(contains('secret-password')));
  });

  test('unverified firmware reaches ready with a warning', () async {
    final harness = _Harness()
      ..ble.bootstrap = const CameraBootstrap(
        model: 'RICOH GR III',
        firmware: '2.00',
        batteryLevel: 80,
        acPowered: false,
        ssid: 'RICOH_secret',
        passphrase: 'secret-password',
      );

    await harness.controller.connect();

    expect((harness.state as ConnectionReady).firmwareWarning, isTrue);
  });

  test('native BLE timeout keeps its stable code', () async {
    final harness = _Harness()
      ..ble.failure = PlatformException(code: 'bleTimeout');

    await harness.controller.connect();

    expect((harness.state as ConnectionFailed).failure.code, 'bleTimeout');
  });

  test('Wi-Fi rejection exposes confirmation guidance', () async {
    final harness = _Harness()
      ..wifi.failure = PlatformException(code: 'wifiUserRejected');

    await harness.controller.connect();

    final failure = (harness.state as ConnectionFailed).failure;
    expect(failure.code, 'wifiUserRejected');
    expect(failure.userAction, ConnectionUserAction.confirmWifi);
  });

  test('HTTP probe failure is retryable', () async {
    final harness = _Harness()..transport.pingStatus = 503;

    await harness.controller.connect();

    final failure = (harness.state as ConnectionFailed).failure;
    expect(failure.stage, ConnectionStage.probing);
    expect(failure.retryable, isTrue);
  });

  test('Wi-Fi loss moves a ready connection to failed', () async {
    final harness = _Harness();
    await harness.controller.connect();

    harness.ble.emit(
      const CameraDeviceEvent(
        type: 'wifiState',
        jsonPayload: '{"state":"lost"}',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect((harness.state as ConnectionFailed).failure.code, 'wifiLost');
  });

  test('cancel ignores stale asynchronous completion', () async {
    final harness = _Harness();
    final scan = Completer<List<BleDeviceCandidate>>();
    harness.ble.scanCompleter = scan;

    final attempt = harness.controller.connect();
    await Future<void>.delayed(Duration.zero);
    await harness.controller.cancel();
    scan.complete(harness.ble.devices);
    await attempt;

    expect(harness.state, isA<ConnectionIdle>());
    expect(harness.trace, isNot(contains('connectBle')));
  });

  test('shutter uses BLE press and release when supported', () async {
    final harness = _Harness();
    await harness.controller.connect();

    await harness.controller.pressShutter();
    await harness.controller.releaseShutter();

    expect(
        harness.trace, containsAllInOrder(['operation:1,1', 'operation:2,1']));
    expect((harness.state as ConnectionReady).lastShutterPath, ShutterPath.ble);
  });

  test('shutter falls back to HTTP when BLE operation is unsupported',
      () async {
    final harness = _Harness()
      ..ble.operationFailure = PlatformException(code: 'unsupported');
    await harness.controller.connect();

    await harness.controller.pressShutter();

    expect(harness.trace, contains('/v1/camera/shoot?af=camera'));
    expect(
        (harness.state as ConnectionReady).lastShutterPath, ShutterPath.http);
  });

  test('fake camera emits a JPEG frame and shutter state', () async {
    final gateways = FakeCameraGateways(stepDelay: Duration.zero);
    addTearDown(gateways.dispose);
    final frame = gateways.transport.liveViewChunks.first;

    await gateways.transport.startLiveView('/v1/liveview');
    await gateways.ble.writeOperationRequest(Uint8List.fromList([1, 1]));

    final bytes = LiveViewParser().add(await frame).single;
    expect(bytes.sublist(0, 2), [0xff, 0xd8]);
    expect(bytes.sublist(bytes.length - 2), [0xff, 0xd9]);
    final codec = await ui.instantiateImageCodec(bytes);
    final decoded = await codec.getNextFrame();
    expect(decoded.image.width, 1);
    expect(decoded.image.height, 1);
    decoded.image.dispose();
    codec.dispose();
    expect(gateways.trace, containsAll(['startLiveView', 'operation:1,1']));
  });

  test('retry resumes at the failed props probe', () async {
    final harness = _Harness()..transport.failPropsOnce = true;
    await harness.controller.connect();
    expect(harness.state, isA<ConnectionFailed>());

    await harness.controller.retry();

    expect(harness.state, isA<ConnectionReady>());
    expect(harness.trace.where((entry) => entry == 'scan'), hasLength(1));
    expect(harness.trace.where((entry) => entry == 'ping'), hasLength(1));
    expect(harness.trace.where((entry) => entry == 'props'), hasLength(2));
  });

  test('manual Wi-Fi reaches ready without BLE and uses camera identity',
      () async {
    final harness = _Harness();
    await harness.controller.connectWifiManually(
      ssid: 'GR_TEST',
      passphrase: '12345678',
    );

    expect(harness.state, isA<ConnectionReady>());
    expect((harness.state as ConnectionReady).snapshot.identity.model,
        'RICOH GR III');
    expect(harness.trace, isNot(contains('scan')));
    expect(harness.trace, isNot(contains('connectBle')));
    expect(harness.trace,
        containsAllInOrder(['connectCameraWifi', 'ping', 'props']));
  });

  test('manual Wi-Fi reads firmwareVersion and battery from camera props',
      () async {
    final harness = _Harness()..transport.useCameraProps = true;
    await harness.controller.connectWifiManually(
      ssid: 'GR_TEST',
      passphrase: '12345678',
    );

    final ready = harness.state as ConnectionReady;
    expect(ready.snapshot.identity.firmware, '2.10');
    expect(ready.snapshot.battery.level, 87);
  });

  test('manual Wi-Fi rejects another camera model after probing', () async {
    final harness = _Harness()..transport.model = 'RICOH GR IIIx';
    await harness.controller.connectWifiManually(
      ssid: 'GR_TEST',
      passphrase: '12345678',
    );

    expect(harness.state, isA<ConnectionFailed>());
    expect(
        (harness.state as ConnectionFailed).failure.code, 'unsupportedCamera');
  });

  test('native BLE phases are exported without device or credential data',
      () async {
    final harness = _Harness();
    harness.ble.emit(const CameraDeviceEvent(
      type: 'bleTrace',
      jsonPayload: '{"phase":"services","status":0,"address":"AA:BB"}',
    ));
    await Future<void>.delayed(Duration.zero);

    final events = harness.container.read(diagnosticStoreProvider).exportJson();
    expect(events, contains('ble.services'));
    expect(events, isNot(contains('AA:BB')));
  });

  test('manual Wi-Fi shutter uses HTTP without trying BLE', () async {
    final harness = _Harness();
    await harness.controller.connectWifiManually(
      ssid: 'GR_TEST',
      passphrase: '12345678',
    );

    await harness.controller.pressShutter();
    await harness.controller.releaseShutter();

    expect(harness.trace, contains('/v1/camera/shoot?af=camera'));
    expect(harness.trace.where((entry) => entry.startsWith('operation:')),
        isEmpty);
  });

  test('manual Wi-Fi probe failure releases the camera network', () async {
    final harness = _Harness()..transport.pingStatus = 503;
    await harness.controller.connectWifiManually(
      ssid: 'GR_TEST',
      passphrase: '12345678',
    );

    expect(harness.state, isA<ConnectionFailed>());
    expect(harness.trace, contains('disconnectWifi'));
  });
}

class _Harness {
  _Harness({
    CameraPermissionStatus permissionStatus = CameraPermissionStatus.granted,
  }) {
    ble = _Ble(trace);
    wifi = _Wifi(trace);
    transport = _Transport(trace);
    provider = NotifierProvider<ConnectionController, CameraConnectionState>(
      () => ConnectionController(
        permissionGate: CameraPermissionGate(
          _PermissionAdapter(permissionStatus),
        ),
        ble: ble,
        wifi: wifi,
        transport: transport,
      ),
    );
    container = ProviderContainer();
    controller = container.read(provider.notifier);
  }

  final trace = <String>[];
  late final _Ble ble;
  late final _Wifi wifi;
  late final _Transport transport;
  late final NotifierProvider<ConnectionController, CameraConnectionState>
      provider;
  late final ProviderContainer container;
  late final ConnectionController controller;

  CameraConnectionState get state => container.read(provider);
}

class _PermissionAdapter implements CameraPermissionAdapter {
  const _PermissionAdapter(this.status);

  final CameraPermissionStatus status;

  @override
  Future<int> androidSdkInt() async => 34;

  @override
  Future<CameraPermissionStatus> request(
    CameraRuntimePermission permission,
  ) async =>
      status;
}

class _Ble implements BleGateway {
  _Ble(this.trace);

  final List<String> trace;
  final _events = StreamController<CameraDeviceEvent>.broadcast();
  List<BleDeviceCandidate> devices = const [
    BleDeviceCandidate(id: 'private-id', name: 'RICOH GR III', rssi: -40),
  ];
  CameraBootstrap bootstrap = const CameraBootstrap(
    model: 'RICOH GR III',
    firmware: '2.10',
    batteryLevel: 80,
    acPowered: false,
    ssid: 'RICOH_secret',
    passphrase: 'secret-password',
  );
  Object? failure;
  Object? operationFailure;
  Completer<List<BleDeviceCandidate>>? scanCompleter;

  void emit(CameraDeviceEvent event) => _events.add(event);

  @override
  Stream<CameraDeviceEvent> get events => _events.stream;

  @override
  Future<List<BleDeviceCandidate>> scan(Duration timeout) async {
    trace.add('scan');
    if (failure case final Object error) throw error;
    return scanCompleter?.future ?? devices;
  }

  @override
  Future<void> connect(String deviceId) async => trace.add('connectBle');

  @override
  Future<void> disconnect() async => trace.add('disconnectBle');

  @override
  Future<CameraBootstrap> readBootstrap() async {
    trace.add('readBootstrap');
    return bootstrap;
  }

  @override
  Future<void> setCameraPower(int value) async =>
      trace.add('setCameraPower:$value');

  @override
  Future<void> setNetworkType(int value) async =>
      trace.add('setNetworkType:$value');

  @override
  Future<void> writeOperationRequest(Uint8List value) async {
    trace.add('operation:${value.join(',')}');
    if (operationFailure case final Object error) throw error;
  }
}

class _Wifi implements WifiGateway {
  _Wifi(this.trace);

  final List<String> trace;
  Object? failure;

  @override
  Future<void> connect(
      {required String ssid, required String passphrase}) async {
    trace.add('connectCameraWifi');
    if (failure case final Object error) throw error;
  }

  @override
  Future<void> disconnect() async => trace.add('disconnectWifi');
}

class _Transport implements CameraTransport {
  _Transport(this.trace);

  final List<String> trace;
  int pingStatus = 200;
  bool failPropsOnce = false;
  String model = 'RICOH GR III';
  bool useCameraProps = false;
  final _chunks = StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get liveViewChunks => _chunks.stream;

  @override
  Future<CameraResponse> request({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    Uint8List? body,
  }) async {
    if (path == '/v1/ping') {
      trace.add('ping');
      return _response(pingStatus, {'pong': true});
    }
    if (path == '/v1/props') {
      trace.add('props');
      if (failPropsOnce) {
        failPropsOnce = false;
        return _response(503, {'errCode': 'busy', 'errMsg': 'busy'});
      }
      return _response(
          200,
          useCameraProps
              ? {'model': model, 'firmwareVersion': '2.10', 'battery': 87}
              : {'model': model, 'firmware': '2.10', 'batteryLevel': 87});
    }
    trace.add(path);
    return _response(200, {});
  }

  @override
  Future<void> startLiveView(String path) async {}

  @override
  Future<void> stopLiveView() async => trace.add('stopLiveView');

  CameraResponse _response(int statusCode, Object value) => CameraResponse(
        statusCode: statusCode,
        headers: const {'content-type': 'application/json'},
        body: Uint8List.fromList(utf8.encode(jsonEncode(value))),
      );
}
