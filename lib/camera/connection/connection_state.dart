import '../gateway/ble_gateway.dart';
import '../model/camera_snapshot.dart';

enum ConnectionStage {
  idle,
  scanning,
  deviceChoice,
  pairing,
  bleReady,
  waking,
  apStarting,
  wifiRequesting,
  wifiBound,
  probing,
  ready,
  failed,
}

enum ConnectionUserAction {
  none,
  retry,
  openSettings,
  confirmWifi,
  chooseDevice,
}

enum ShutterPath { ble, http }

class ConnectionFailure {
  const ConnectionFailure({
    required this.stage,
    required this.code,
    required this.retryable,
    required this.userAction,
    required this.redactedDetail,
  });

  final ConnectionStage stage;
  final String code;
  final bool retryable;
  final ConnectionUserAction userAction;
  final String redactedDetail;

  @override
  String toString() => 'ConnectionFailure('
      'stage: ${stage.name}, code: $code, retryable: $retryable, '
      'userAction: ${userAction.name}, detail: $redactedDetail)';
}

sealed class CameraConnectionState {
  const CameraConnectionState();

  ConnectionStage get stage;
}

final class ConnectionIdle extends CameraConnectionState {
  const ConnectionIdle();

  @override
  ConnectionStage get stage => ConnectionStage.idle;
}

final class ConnectionScanning extends CameraConnectionState {
  const ConnectionScanning();

  @override
  ConnectionStage get stage => ConnectionStage.scanning;
}

final class ConnectionDeviceChoice extends CameraConnectionState {
  const ConnectionDeviceChoice(this.devices);

  final List<BleDeviceCandidate> devices;

  @override
  ConnectionStage get stage => ConnectionStage.deviceChoice;
}

final class ConnectionPairing extends CameraConnectionState {
  const ConnectionPairing(this.deviceName);

  final String deviceName;

  @override
  ConnectionStage get stage => ConnectionStage.pairing;
}

final class ConnectionBleReady extends CameraConnectionState {
  const ConnectionBleReady(this.snapshot);

  final CameraSnapshot snapshot;

  @override
  ConnectionStage get stage => ConnectionStage.bleReady;
}

final class ConnectionWaking extends CameraConnectionState {
  const ConnectionWaking(this.snapshot);

  final CameraSnapshot snapshot;

  @override
  ConnectionStage get stage => ConnectionStage.waking;
}

final class ConnectionApStarting extends CameraConnectionState {
  const ConnectionApStarting(this.snapshot);

  final CameraSnapshot snapshot;

  @override
  ConnectionStage get stage => ConnectionStage.apStarting;
}

final class ConnectionWifiRequesting extends CameraConnectionState {
  const ConnectionWifiRequesting(this.snapshot);

  final CameraSnapshot snapshot;

  @override
  ConnectionStage get stage => ConnectionStage.wifiRequesting;
}

final class ConnectionWifiManualRequesting extends CameraConnectionState {
  const ConnectionWifiManualRequesting();

  @override
  ConnectionStage get stage => ConnectionStage.wifiRequesting;
}

final class ConnectionWifiManualProbing extends CameraConnectionState {
  const ConnectionWifiManualProbing();

  @override
  ConnectionStage get stage => ConnectionStage.probing;
}

final class ConnectionWifiBound extends CameraConnectionState {
  const ConnectionWifiBound(this.snapshot);

  final CameraSnapshot snapshot;

  @override
  ConnectionStage get stage => ConnectionStage.wifiBound;
}

final class ConnectionProbing extends CameraConnectionState {
  const ConnectionProbing(this.snapshot);

  final CameraSnapshot snapshot;

  @override
  ConnectionStage get stage => ConnectionStage.probing;
}

final class ConnectionReady extends CameraConnectionState {
  const ConnectionReady({
    required this.snapshot,
    required this.firmwareWarning,
    this.lastShutterPath,
    this.wifiOnly = false,
  });

  final CameraSnapshot snapshot;
  final bool firmwareWarning;
  final ShutterPath? lastShutterPath;
  final bool wifiOnly;

  ConnectionReady copyWith({ShutterPath? lastShutterPath}) => ConnectionReady(
        snapshot: snapshot,
        firmwareWarning: firmwareWarning,
        lastShutterPath: lastShutterPath ?? this.lastShutterPath,
        wifiOnly: wifiOnly,
      );

  @override
  ConnectionStage get stage => ConnectionStage.ready;
}

final class ConnectionFailed extends CameraConnectionState {
  const ConnectionFailed(this.failure);

  final ConnectionFailure failure;

  @override
  ConnectionStage get stage => ConnectionStage.failed;

  @override
  String toString() => 'ConnectionFailed($failure)';
}
