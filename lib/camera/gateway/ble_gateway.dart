import 'dart:async';
import 'dart:typed_data';

class BleDeviceCandidate {
  const BleDeviceCandidate({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;

  @override
  String toString() =>
      'BleDeviceCandidate(name: $name, rssi: $rssi, id: <redacted>)';
}

class CameraBootstrap {
  const CameraBootstrap({
    required this.model,
    required this.firmware,
    required this.batteryLevel,
    required this.acPowered,
    required this.ssid,
    required this.passphrase,
  });

  final String model;
  final String firmware;
  final int batteryLevel;
  final bool acPowered;
  final String ssid;
  final String passphrase;

  @override
  String toString() => 'CameraBootstrap('
      'model: $model, firmware: $firmware, batteryLevel: $batteryLevel, '
      'acPowered: $acPowered, ssid: <redacted>, passphrase: <redacted>)';
}

class CameraDeviceEvent {
  const CameraDeviceEvent({required this.type, required this.jsonPayload});

  final String type;
  final String jsonPayload;
}

abstract interface class BleGateway {
  Stream<CameraDeviceEvent> get events;

  Future<List<BleDeviceCandidate>> scan(Duration timeout);

  Future<void> connect(String deviceId);

  Future<void> disconnect();

  Future<CameraBootstrap> readBootstrap();

  Future<void> setCameraPower(int value);

  Future<void> setNetworkType(int value);

  Future<void> writeOperationRequest(Uint8List value);
}
