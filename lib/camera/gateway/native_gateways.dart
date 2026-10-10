import 'dart:async';
import 'dart:typed_data';

import '../../platform/device_api.g.dart' as pigeon;
import 'ble_gateway.dart';
import 'camera_transport.dart';
import 'change_socket.dart';
import 'wifi_gateway.dart';

abstract interface class CameraGatewayBundle {
  BleGateway get ble;
  WifiGateway get wifi;
  CameraTransport get transport;
  ChangeSocket get changes;
  DeviceScreen get screen;

  void dispose();
}

class NativeCameraGateways implements CameraGatewayBundle {
  NativeCameraGateways({pigeon.CameraDeviceHostApi? hostApi})
      : _hostApi = hostApi ?? pigeon.CameraDeviceHostApi() {
    _callbacks = _NativeCallbacks();
    pigeon.CameraDeviceFlutterApi.setUp(_callbacks);
    ble = _NativeBleGateway(this);
    wifi = _NativeWifiGateway(this);
    transport = _NativeCameraTransport(this);
    changes = _NativeChangeSocket(this);
    screen = _NativeDeviceScreen(this);
  }

  final pigeon.CameraDeviceHostApi _hostApi;
  late final _NativeCallbacks _callbacks;
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

  var _disconnected = true;
  Future<void>? _disconnecting;

  void markConnected() => _disconnected = false;

  Future<void> disconnectAll() async {
    final active = _disconnecting;
    if (active != null) return active;
    if (_disconnected) return;
    _disconnected = true;
    final operation = _hostApi.disconnectBle();
    _disconnecting = operation;
    try {
      await operation;
    } finally {
      _disconnecting = null;
    }
  }

  @override
  void dispose() {
    pigeon.CameraDeviceFlutterApi.setUp(null);
    unawaited(disconnectAll().catchError((Object _) {}));
    _callbacks.dispose();
  }
}

class _NativeBleGateway implements BleGateway {
  const _NativeBleGateway(this._owner);

  final NativeCameraGateways _owner;

  @override
  Stream<CameraDeviceEvent> get events => _owner._callbacks.events;

  @override
  Future<List<BleDeviceCandidate>> scan(Duration timeout) async {
    final devices = await _owner._hostApi.scan(timeout.inMilliseconds);
    return devices.whereType<pigeon.NativeBleDevice>().map((device) {
      final id = device.id;
      final name = device.name;
      final rssi = device.rssi;
      if (id == null || name == null || rssi == null) {
        throw const NativeContractViolation('scan.device');
      }
      return BleDeviceCandidate(id: id, name: name, rssi: rssi);
    }).toList(growable: false);
  }

  @override
  Future<void> connect(String deviceId) async {
    await _owner._hostApi.connectBle(deviceId);
    _owner.markConnected();
  }

  @override
  Future<void> disconnect() => _owner.disconnectAll();

  @override
  Future<CameraBootstrap> readBootstrap() async {
    final value = await _owner._hostApi.readBootstrap();
    final model = value.model;
    final firmware = value.firmware;
    final batteryLevel = value.batteryLevel;
    final acPowered = value.acPowered;
    final ssid = value.ssid;
    final passphrase = value.passphrase;
    if (model == null ||
        firmware == null ||
        batteryLevel == null ||
        acPowered == null ||
        ssid == null ||
        passphrase == null) {
      throw const NativeContractViolation('bootstrap');
    }
    return CameraBootstrap(
      model: model,
      firmware: firmware,
      batteryLevel: batteryLevel,
      acPowered: acPowered,
      ssid: ssid,
      passphrase: passphrase,
    );
  }

  @override
  Future<void> setCameraPower(int value) =>
      _owner._hostApi.setCameraPower(value);

  @override
  Future<void> setNetworkType(int value) =>
      _owner._hostApi.setNetworkType(value);

  @override
  Future<void> writeOperationRequest(Uint8List value) =>
      _owner._hostApi.writeOperationRequest(value);
}

class _NativeWifiGateway implements WifiGateway {
  const _NativeWifiGateway(this._owner);

  final NativeCameraGateways _owner;

  @override
  Future<void> connect(
      {required String ssid, required String passphrase}) async {
    await _owner._hostApi.connectCameraWifi(ssid, passphrase);
    _owner.markConnected();
  }

  @override
  Future<void> disconnect() => _owner.disconnectAll();
}

class _NativeCameraTransport implements CameraTransport {
  const _NativeCameraTransport(this._owner);

  final NativeCameraGateways _owner;

  @override
  Stream<Uint8List> get liveViewChunks => _owner._callbacks.liveViewChunks;

  @override
  Future<CameraResponse> request({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    Uint8List? body,
  }) async {
    final response = await _owner._hostApi.cameraRequest(
      method,
      path,
      headers,
      body,
    );
    final statusCode = response.statusCode;
    final nativeHeaders = response.headers;
    final responseBody = response.body;
    if (statusCode == null || nativeHeaders == null || responseBody == null) {
      throw const NativeContractViolation('httpResponse');
    }
    final safeHeaders = <String, String>{};
    for (final entry in nativeHeaders.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key == null || value == null) {
        throw const NativeContractViolation('httpResponse.headers');
      }
      safeHeaders[key] = value;
    }
    return CameraResponse(
      statusCode: statusCode,
      headers: safeHeaders,
      body: responseBody,
    );
  }

  @override
  Future<void> startLiveView(String path) =>
      _owner._hostApi.startLiveView(path);

  @override
  Future<void> stopLiveView() => _owner._hostApi.stopLiveView();
}

class _NativeChangeSocket implements ChangeSocket {
  const _NativeChangeSocket(this._owner);

  final NativeCameraGateways _owner;

  @override
  Stream<ChangeSocketEvent> get events => _owner._callbacks.events
      .map(changeSocketEventFrom)
      .where((event) => event != null)
      .cast<ChangeSocketEvent>();

  @override
  Future<void> open(String path) => _owner._hostApi.openChangeSocket(path);

  @override
  Future<void> close() => _owner._hostApi.closeChangeSocket();
}

class _NativeDeviceScreen implements DeviceScreen {
  const _NativeDeviceScreen(this._owner);

  final NativeCameraGateways _owner;

  @override
  Future<void> setKeepScreenOn(bool on) => _owner._hostApi.setKeepScreenOn(on);
}

class _NativeCallbacks extends pigeon.CameraDeviceFlutterApi {
  final _events = StreamController<CameraDeviceEvent>.broadcast();
  final _liveViewChunks = StreamController<Uint8List>.broadcast();

  Stream<CameraDeviceEvent> get events => _events.stream;
  Stream<Uint8List> get liveViewChunks => _liveViewChunks.stream;

  @override
  void onLiveViewChunk(Uint8List bytes) => _liveViewChunks.add(bytes);

  @override
  void onNativeEvent(String type, String jsonPayload) =>
      _events.add(CameraDeviceEvent(type: type, jsonPayload: jsonPayload));

  void dispose() {
    unawaited(_events.close());
    unawaited(_liveViewChunks.close());
  }
}
