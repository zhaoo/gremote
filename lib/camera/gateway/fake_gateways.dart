import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'ble_gateway.dart';
import 'camera_transport.dart';
import 'change_socket.dart';
import 'fake_camera_model.dart';
import 'native_gateways.dart';
import 'wifi_gateway.dart';

class FakeCameraGateways implements CameraGatewayBundle {
  FakeCameraGateways({
    this.stepDelay = const Duration(milliseconds: 150),
    CameraBootstrap? bootstrap,
    FakeCameraModel? camera,
  })  : camera = camera ?? FakeCameraModel(),
        bootstrap = bootstrap ??
            CameraBootstrap(
              model: 'RICOH GR III',
              firmware: '2.10',
              batteryLevel: 82,
              acPowered: false,
              ssid: 'RICOH_GR_III',
              passphrase: _ephemeralPassphrase(),
            ) {
    ble = _FakeBleGateway(this);
    wifi = _FakeWifiGateway(this);
    transport = _FakeCameraTransport(this);
    changes = _FakeChangeSocket(this);
    screen = _FakeDeviceScreen(this);
  }

  final Duration stepDelay;
  final CameraBootstrap bootstrap;
  final FakeCameraModel camera;

  static String _ephemeralPassphrase() {
    final random = Random.secure();
    return base64Url.encode(List<int>.generate(18, (_) => random.nextInt(256)));
  }

  final trace = <String>[];
  final _events = StreamController<CameraDeviceEvent>.broadcast();
  final _chunks = StreamController<Uint8List>.broadcast();

  @override
  late final BleGateway ble;
  @override
  late final WifiGateway wifi;
  @override
  late final CameraTransport transport;
  @override
  late final ChangeSocket changes;
  @override
  late final DeviceScreen screen;

  Future<void> wait() => Future<void>.delayed(stepDelay);

  void record(String value) => trace.add(value);

  @override
  void dispose() {
    unawaited(_events.close());
    unawaited(_chunks.close());
    camera.dispose();
  }
}

class _FakeBleGateway implements BleGateway {
  const _FakeBleGateway(this._owner);

  final FakeCameraGateways _owner;

  @override
  Stream<CameraDeviceEvent> get events => _owner._events.stream;

  @override
  Future<List<BleDeviceCandidate>> scan(Duration timeout) async {
    _owner.record('scan');
    await _owner.wait();
    return const [
      BleDeviceCandidate(
        id: 'fake-device-id',
        name: 'RICOH GR III',
        rssi: -42,
      ),
    ];
  }

  @override
  Future<void> connect(String deviceId) async {
    _owner.record('connectBle');
    await _owner.wait();
  }

  @override
  Future<void> disconnect() async => _owner.record('disconnectBle');

  @override
  Future<CameraBootstrap> readBootstrap() async {
    _owner.record('readBootstrap');
    await _owner.wait();
    return _owner.bootstrap;
  }

  @override
  Future<void> setCameraPower(int value) async {
    _owner.record('setCameraPower:$value');
    await _owner.wait();
  }

  @override
  Future<void> setNetworkType(int value) async {
    _owner.record('setNetworkType:$value');
    await _owner.wait();
  }

  @override
  Future<void> writeOperationRequest(Uint8List value) async {
    _owner.record('operation:${value.join(',')}');
    await _owner.wait();
    if (value.first == 2) _owner.camera.shutter();
    _owner._events.add(
      CameraDeviceEvent(
        type: 'captureStatus',
        jsonPayload:
            jsonEncode({'state': value.first == 1 ? 'pressed' : 'idle'}),
      ),
    );
  }
}

class _FakeWifiGateway implements WifiGateway {
  const _FakeWifiGateway(this._owner);

  final FakeCameraGateways _owner;

  @override
  Future<void> connect(
      {required String ssid, required String passphrase}) async {
    _owner.record('connectCameraWifi');
    await _owner.wait();
  }

  @override
  Future<void> disconnect() async => _owner.record('disconnectWifi');
}

class _FakeCameraTransport implements CameraTransport {
  const _FakeCameraTransport(this._owner);

  final FakeCameraGateways _owner;

  @override
  Stream<Uint8List> get liveViewChunks => _owner._chunks.stream;

  @override
  Future<CameraResponse> request({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    Uint8List? body,
  }) async {
    _owner.record(path == '/v1/ping'
        ? 'ping'
        : path == '/v1/props'
            ? 'props'
            : path);
    await _owner.wait();
    return _owner.camera.handle(method, path, headers: headers, body: body);
  }

  @override
  Future<void> startLiveView(String path) async {
    _owner.record('startLiveView');
    await _owner.wait();
    final frame = base64Decode(fakeJpegBase64);
    _owner._chunks.add(
      Uint8List.fromList([
        ...ascii.encode(
          '--boundary\r\nContent-Type: image/jpeg\r\n'
          'Content-Length: ${frame.length}\r\n\r\n',
        ),
        ...frame,
        ...ascii.encode('\r\n--boundary--\r\n'),
      ]),
    );
  }

  @override
  Future<void> stopLiveView() async => _owner.record('stopLiveView');
}

class _FakeChangeSocket implements ChangeSocket {
  const _FakeChangeSocket(this._owner);

  final FakeCameraGateways _owner;

  @override
  Stream<ChangeSocketEvent> get events => _owner.camera.socketEvents;

  @override
  Future<void> open(String path) {
    _owner.record('openChanges');
    return _owner.camera.openSocket(path);
  }

  @override
  Future<void> close() {
    _owner.record('closeChanges');
    return _owner.camera.closeSocket();
  }
}

class _FakeDeviceScreen implements DeviceScreen {
  const _FakeDeviceScreen(this._owner);

  final FakeCameraGateways _owner;

  @override
  Future<void> setKeepScreenOn(bool on) async =>
      _owner.record('keepScreenOn:$on');
}
