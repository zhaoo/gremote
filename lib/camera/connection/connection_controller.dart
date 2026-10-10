import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../diagnostics/diagnostic_event.dart';
import '../../diagnostics/diagnostic_store.dart';
import '../../platform/camera_permission_gate.dart';
import '../gateway/ble_gateway.dart';
import '../gateway/camera_transport.dart';
import '../gateway/fake_gateways.dart';
import '../gateway/native_gateways.dart';
import '../gateway/wifi_gateway.dart';
import '../http/camera_api.dart';
import '../model/camera_identity.dart';
import '../model/camera_snapshot.dart';
import '../protocol/ble_codecs.dart';
import '../protocol/props_parser.dart';
import 'connection_state.dart';

const useFakeCamera = bool.fromEnvironment('GREMOTE_FAKE_CAMERA');

final cameraGatewaysProvider = Provider<CameraGatewayBundle>((ref) {
  final gateways =
      useFakeCamera ? FakeCameraGateways() : NativeCameraGateways();
  ref.onDispose(gateways.dispose);
  return gateways;
});

final cameraPermissionGateProvider = Provider<CameraPermissionGate>((ref) {
  if (useFakeCamera) {
    return const CameraPermissionGate(GrantedCameraPermissionAdapter());
  }
  return CameraPermissionGate(PermissionHandlerCameraPermissionAdapter());
});

final connectionControllerProvider =
    NotifierProvider<ConnectionController, CameraConnectionState>(
  ConnectionController.new,
);

enum _ConnectionStep {
  permissions,
  scan,
  pairing,
  bootstrap,
  wake,
  accessPoint,
  wifi,
  ping,
  props,
}

class ConnectionController extends Notifier<CameraConnectionState> {
  ConnectionController({
    CameraPermissionGate? permissionGate,
    BleGateway? ble,
    WifiGateway? wifi,
    CameraTransport? transport,
    DiagnosticStore? diagnostics,
  })  : _providedPermissionGate = permissionGate,
        _providedBle = ble,
        _providedWifi = wifi,
        _providedTransport = transport,
        _providedDiagnostics = diagnostics;

  final CameraPermissionGate? _providedPermissionGate;
  final BleGateway? _providedBle;
  final WifiGateway? _providedWifi;
  final CameraTransport? _providedTransport;
  final DiagnosticStore? _providedDiagnostics;

  late final CameraPermissionGate _permissionGate;
  late final BleGateway _ble;
  late final WifiGateway _wifi;
  late final CameraTransport _transport;
  late final CameraApi _api;
  late final DiagnosticStore _diagnostics;
  final Stopwatch _clock = Stopwatch()..start();
  var _lastDiagnosticMicros = 0;
  var _retryCount = 0;
  StreamSubscription<CameraDeviceEvent>? _eventSubscription;
  var _generation = 0;
  var _activeStage = ConnectionStage.idle;
  var _retryStep = _ConnectionStep.permissions;
  BleDeviceCandidate? _selectedDevice;
  CameraBootstrap? _bootstrap;
  CameraSnapshot? _snapshot;

  @override
  CameraConnectionState build() {
    final bundle = _needsBundle ? ref.read(cameraGatewaysProvider) : null;
    _permissionGate =
        _providedPermissionGate ?? ref.read(cameraPermissionGateProvider);
    _ble = _providedBle ?? bundle!.ble;
    _wifi = _providedWifi ?? bundle!.wifi;
    _transport = _providedTransport ?? bundle!.transport;
    _api = CameraApi(_transport);
    _diagnostics = _providedDiagnostics ?? ref.read(diagnosticStoreProvider);
    _eventSubscription = _ble.events.listen(_onDeviceEvent);
    ref.onDispose(() => unawaited(_eventSubscription?.cancel()));
    return const ConnectionIdle();
  }

  bool get _needsBundle =>
      _providedBle == null ||
      _providedWifi == null ||
      _providedTransport == null;

  Future<void> connect({String? deviceId}) async {
    final generation = ++_generation;
    _selectedDevice = null;
    _bootstrap = null;
    _snapshot = null;
    _retryCount = 0;
    await _run(generation, _ConnectionStep.permissions, deviceId: deviceId);
  }

  Future<void> selectDevice(String deviceId) async {
    final current = state;
    if (current is! ConnectionDeviceChoice) return;
    final selected =
        current.devices.where((item) => item.id == deviceId).firstOrNull;
    if (selected == null) return;
    _selectedDevice = selected;
    await _run(++_generation, _ConnectionStep.pairing);
  }

  Future<void> connectWifiManually({
    required String ssid,
    required String passphrase,
  }) async {
    final generation = ++_generation;
    _selectedDevice = null;
    _bootstrap = null;
    _snapshot = null;
    _retryCount = 0;
    try {
      _activeStage = ConnectionStage.wifiRequesting;
      await _permissionGate.ensureWifiGranted();
      _check(generation);
      _setState(generation, const ConnectionWifiManualRequesting());
      await _wifi.connect(ssid: ssid, passphrase: passphrase);
      _check(generation);
      _setState(generation, const ConnectionWifiManualProbing());
      await _api.ping();
      final props = await _api.props();
      _check(generation);
      final firmware = props['firmwareVersion'] ?? props['firmware'];
      final identity = CameraIdentity(
        model: props['model'] is String ? props['model']! as String : '',
        firmware: firmware is String ? firmware : '',
      );
      if (!identity.isSupportedModel) {
        throw const _ConnectionFault('unsupportedCamera');
      }
      final battery = parseProps(props).status.battery ?? props['batteryLevel'];
      _snapshot = CameraSnapshot(
        identity: identity,
        battery: CameraBattery(
          level:
              battery is int && battery >= 0 && battery <= 100 ? battery : -1,
          acPowered: false,
        ),
      );
      _setState(
          generation,
          ConnectionReady(
            snapshot: _snapshot!,
            firmwareWarning: !identity.isVerifiedFirmware,
            wifiOnly: true,
          ));
    } on _StaleAttempt {
      return;
    } catch (error) {
      if (generation != _generation) return;
      try {
        await _wifi.disconnect();
      } catch (_) {
        // Preserve the original connection failure.
      }
      final failure = _mapFailure(_activeStage, error);
      state = ConnectionFailed(ConnectionFailure(
        stage: failure.stage,
        code: failure.code,
        retryable: false,
        userAction: failure.userAction,
        redactedDetail: failure.redactedDetail,
      ));
      _recordDiagnostic(stage: failure.stage, exceptionCode: failure.code);
    }
  }

  Future<void> retry() async {
    final current = state;
    if (current is! ConnectionFailed || !current.failure.retryable) return;
    _retryCount++;
    await _run(++_generation, _retryStep);
  }

  Future<void> pressShutter() async {
    final current = state;
    if (current is! ConnectionReady) return;
    if (current.wifiOnly) {
      await _api.shoot(autoFocus: true);
      if (state case final ConnectionReady ready) {
        state = ready.copyWith(lastShutterPath: ShutterPath.http);
      }
      return;
    }
    try {
      await _ble.writeOperationRequest(
        encodeOperationRequest(start: true, autoFocus: true),
      );
      if (state case final ConnectionReady ready) {
        state = ready.copyWith(lastShutterPath: ShutterPath.ble);
      }
    } on PlatformException catch (error) {
      if (error.code != 'unsupported') rethrow;
      await _api.shoot(autoFocus: true);
      if (state case final ConnectionReady ready) {
        state = ready.copyWith(lastShutterPath: ShutterPath.http);
      }
    }
  }

  Future<void> releaseShutter() async {
    final current = state;
    if (current is! ConnectionReady ||
        current.lastShutterPath == ShutterPath.http) {
      return;
    }
    await _ble.writeOperationRequest(
      encodeOperationRequest(start: false, autoFocus: true),
    );
  }

  Future<void> cancel() async {
    final generation = ++_generation;
    _retryStep = _ConnectionStep.permissions;
    await _transport.stopLiveView();
    await _wifi.disconnect();
    await _ble.disconnect();
    if (generation == _generation) state = const ConnectionIdle();
  }

  Future<void> _run(
    int generation,
    _ConnectionStep start, {
    String? deviceId,
  }) async {
    var step = start;
    try {
      if (step.index <= _ConnectionStep.permissions.index) {
        step = _ConnectionStep.permissions;
        _retryStep = step;
        _activeStage = ConnectionStage.idle;
        await _permissionGate.ensureGranted();
        _check(generation);
      }

      if (step.index <= _ConnectionStep.scan.index) {
        step = _ConnectionStep.scan;
        _retryStep = step;
        _setState(generation, const ConnectionScanning());
        final devices = await _ble.scan(const Duration(seconds: 8));
        _check(generation);
        if (devices.isEmpty) {
          throw const _ConnectionFault('cameraNotFound');
        }
        if (deviceId == null && devices.length > 1) {
          _setState(generation, ConnectionDeviceChoice(devices));
          return;
        }
        _selectedDevice = deviceId == null
            ? devices.first
            : devices.where((item) => item.id == deviceId).firstOrNull;
        if (_selectedDevice == null) {
          throw const _ConnectionFault('cameraNotFound');
        }
      }

      if (step.index <= _ConnectionStep.pairing.index) {
        step = _ConnectionStep.pairing;
        _retryStep = step;
        final selected = _selectedDevice ??
            (throw const _ConnectionFault('cameraSelectionLost'));
        _setState(generation, ConnectionPairing(selected.name));
        await _ble.connect(selected.id);
        _check(generation);
      }

      if (step.index <= _ConnectionStep.bootstrap.index) {
        step = _ConnectionStep.bootstrap;
        _retryStep = step;
        final bootstrap = await _ble.readBootstrap();
        _check(generation);
        final identity = CameraIdentity(
          model: bootstrap.model,
          firmware: bootstrap.firmware,
        );
        if (!identity.isSupportedModel) {
          throw const _ConnectionFault('unsupportedCamera');
        }
        _bootstrap = bootstrap;
        _snapshot = CameraSnapshot(
          identity: identity,
          battery: CameraBattery(
            level: bootstrap.batteryLevel,
            acPowered: bootstrap.acPowered,
          ),
        );
        _setState(generation, ConnectionBleReady(_snapshot!));
      }

      if (step.index <= _ConnectionStep.wake.index) {
        step = _ConnectionStep.wake;
        _retryStep = step;
        _setState(generation, ConnectionWaking(_requireSnapshot()));
        await _ble.setCameraPower(1);
        _check(generation);
      }

      if (step.index <= _ConnectionStep.accessPoint.index) {
        step = _ConnectionStep.accessPoint;
        _retryStep = step;
        _setState(generation, ConnectionApStarting(_requireSnapshot()));
        await _ble.setNetworkType(1);
        _check(generation);
      }

      if (step.index <= _ConnectionStep.wifi.index) {
        step = _ConnectionStep.wifi;
        _retryStep = step;
        _setState(generation, ConnectionWifiRequesting(_requireSnapshot()));
        final bootstrap =
            _bootstrap ?? (throw const _ConnectionFault('bootstrapStateLost'));
        await _wifi.connect(
          ssid: bootstrap.ssid,
          passphrase: bootstrap.passphrase,
        );
        _check(generation);
        _setState(generation, ConnectionWifiBound(_requireSnapshot()));
      }

      if (step.index <= _ConnectionStep.ping.index) {
        step = _ConnectionStep.ping;
        _retryStep = step;
        _setState(generation, ConnectionProbing(_requireSnapshot()));
        await _api.ping();
        _check(generation);
      }

      if (step.index <= _ConnectionStep.props.index) {
        step = _ConnectionStep.props;
        _retryStep = step;
        await _api.props();
        _check(generation);
      }

      final snapshot = _requireSnapshot();
      _setState(
        generation,
        ConnectionReady(
          snapshot: snapshot,
          firmwareWarning: !snapshot.identity.isVerifiedFirmware,
        ),
      );
    } on _StaleAttempt {
      return;
    } catch (error) {
      if (generation != _generation) return;
      _retryStep = step;
      final failure = _mapFailure(_activeStage, error);
      state = ConnectionFailed(failure);
      _recordDiagnostic(
        stage: failure.stage,
        exceptionCode: failure.code,
        statusCode: error is CameraApiException ? error.statusCode : null,
      );
    }
  }

  CameraSnapshot _requireSnapshot() =>
      _snapshot ?? (throw const _ConnectionFault('snapshotStateLost'));

  void _setState(int generation, CameraConnectionState next) {
    _check(generation);
    _activeStage = next.stage;
    state = next;
    _recordDiagnostic(stage: next.stage);
  }

  void _recordDiagnostic({
    required ConnectionStage stage,
    String? exceptionCode,
    int? statusCode,
  }) {
    final now = _clock.elapsedMicroseconds;
    _diagnostics.record(
      DiagnosticEvent(
        stage: stage.name,
        monotonicMicros: now,
        durationMs: (now - _lastDiagnosticMicros) ~/ 1000,
        retryCount: _retryCount,
        firmware: _snapshot?.identity.firmware,
        statusCode: statusCode,
        exceptionCode: exceptionCode,
      ),
    );
    _lastDiagnosticMicros = now;
  }

  void _check(int generation) {
    if (generation != _generation) throw const _StaleAttempt();
  }

  void _onDeviceEvent(CameraDeviceEvent event) {
    if (event.type == 'bleTrace') {
      final payload = _jsonObject(event.jsonPayload);
      const phases = {
        'connected',
        'disconnected',
        'mtu',
        'services',
        'connectTimeout',
        'readModel',
        'readFirmware',
        'readBattery',
        'batteryLength',
        'readSsid',
        'readPassphrase',
        'readComplete',
        'operationFailure',
      };
      final phase = payload?['phase'];
      if (phase is String && phases.contains(phase)) {
        final status = payload?['status'];
        final now = _clock.elapsedMicroseconds;
        _diagnostics.record(DiagnosticEvent(
          stage: 'ble.$phase',
          monotonicMicros: now,
          durationMs: (now - _lastDiagnosticMicros) ~/ 1000,
          retryCount: _retryCount,
          statusCode: status is int ? status : null,
        ));
        _lastDiagnosticMicros = now;
      }
      return;
    }
    if (event.type != 'wifiState' || state is ConnectionIdle) return;
    final payload = _jsonObject(event.jsonPayload);
    if (payload?['state'] != 'lost') return;
    _generation++;
    _retryStep = _ConnectionStep.wifi;
    const failure = ConnectionFailure(
      stage: ConnectionStage.wifiBound,
      code: 'wifiLost',
      retryable: true,
      userAction: ConnectionUserAction.retry,
      redactedDetail: 'wifiLost',
    );
    state = const ConnectionFailed(failure);
    _recordDiagnostic(
      stage: failure.stage,
      exceptionCode: failure.code,
    );
  }

  ConnectionFailure _mapFailure(ConnectionStage stage, Object error) {
    final code = switch (error) {
      PlatformException() => error.code,
      CameraApiException() => error.cameraCode ?? error.code,
      NativeContractViolation() => 'nativeContractViolation',
      CameraPermissionException() => error.code,
      _ConnectionFault() => error.code,
      _ => 'connectionFailed',
    };
    final action = switch (error) {
      CameraPermissionException(
        repairAction: PermissionRepairAction.openSettings,
      ) =>
        ConnectionUserAction.openSettings,
      CameraPermissionException() => ConnectionUserAction.retry,
      PlatformException(code: 'wifiUserRejected') =>
        ConnectionUserAction.confirmWifi,
      PlatformException(code: 'bluetoothDisabled') =>
        ConnectionUserAction.openSettings,
      _ConnectionFault(code: 'unsupportedCamera') => ConnectionUserAction.none,
      _ => ConnectionUserAction.retry,
    };
    final retryable = code != 'unsupportedCamera' &&
        code != 'permissionPermanentlyDenied' &&
        code != 'nativeContractViolation';
    return ConnectionFailure(
      stage: stage,
      code: code,
      retryable: retryable,
      userAction: action,
      redactedDetail: code,
    );
  }

  Map<String, Object?>? _jsonObject(String source) {
    try {
      final value = jsonDecode(source);
      return value is Map<String, Object?> ? value : null;
    } on FormatException {
      return null;
    }
  }
}

class _ConnectionFault implements Exception {
  const _ConnectionFault(this.code);

  final String code;
}

class _StaleAttempt implements Exception {
  const _StaleAttempt();
}
