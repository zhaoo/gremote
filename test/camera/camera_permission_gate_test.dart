import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/platform/camera_permission_gate.dart';

void main() {
  test('iOS requests Bluetooth without Android Wi-Fi or location permissions',
      () async {
    final adapter = _FakePermissionAdapter(0);
    final gate = CameraPermissionGate(adapter, isIOS: true);
    await gate.ensureGranted();
    expect(adapter.requested, [CameraRuntimePermission.bluetooth]);
    adapter.requested.clear();
    await gate.ensureWifiGranted();
    expect(adapter.requested, isEmpty);
  });
  test('concurrent permission checks share the pending system request',
      () async {
    final adapter = _PendingPermissionAdapter();
    final gate = CameraPermissionGate(adapter);
    final first = gate.ensureGranted();
    final second = gate.ensureGranted();
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requested, [CameraRuntimePermission.bluetoothScan]);
    adapter.approval.complete(CameraPermissionStatus.granted);
    await Future.wait([first, second]);
    expect(adapter.requested, [
      CameraRuntimePermission.bluetoothScan,
      CameraRuntimePermission.bluetoothConnect,
      CameraRuntimePermission.nearbyWifi,
    ]);
  });

  test('manual Wi-Fi waits for the in-flight Bluetooth permission sequence',
      () async {
    final adapter = _PendingPermissionAdapter();
    final gate = CameraPermissionGate(adapter);
    final first = gate.ensureGranted();
    final manual = gate.ensureWifiGranted();
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requested, [CameraRuntimePermission.bluetoothScan]);
    adapter.approval.complete(CameraPermissionStatus.granted);
    await Future.wait([first, manual]);
  });

  test('Bluetooth check after a pending Wi-Fi check still requests Bluetooth',
      () async {
    final adapter = _PendingPermissionAdapter();
    final gate = CameraPermissionGate(adapter);
    final wifi = gate.ensureWifiGranted();
    final bluetooth = gate.ensureGranted();
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requested, [CameraRuntimePermission.nearbyWifi]);
    adapter.approval.complete(CameraPermissionStatus.granted);
    await Future.wait([wifi, bluetooth]);
    expect(adapter.requested, [
      CameraRuntimePermission.nearbyWifi,
      CameraRuntimePermission.bluetoothScan,
      CameraRuntimePermission.bluetoothConnect,
      CameraRuntimePermission.nearbyWifi,
    ]);
  });

  test(
      'manual Wi-Fi can grant after the overlapping Bluetooth prompt is denied',
      () async {
    final adapter = _BluetoothDeniedPermissionAdapter();
    final gate = CameraPermissionGate(adapter);
    final bluetooth = _capture(gate.ensureGranted);
    final wifi = _capture(gate.ensureWifiGranted);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requested, [CameraRuntimePermission.bluetoothScan]);
    adapter.bluetoothDecision.complete(CameraPermissionStatus.denied);

    expect(await bluetooth, isA<CameraPermissionException>());
    expect(await wifi, isNull);
    expect(adapter.requested, [
      CameraRuntimePermission.bluetoothScan,
      CameraRuntimePermission.nearbyWifi,
    ]);
  });

  test('SDK 33+ requests Bluetooth and nearby Wi-Fi permissions', () async {
    final adapter = _FakePermissionAdapter(34);

    await CameraPermissionGate(adapter).ensureGranted();

    expect(
      adapter.requested,
      [
        CameraRuntimePermission.bluetoothScan,
        CameraRuntimePermission.bluetoothConnect,
        CameraRuntimePermission.nearbyWifi,
      ],
    );
  });

  test('SDK 31-32 also requests foreground location', () async {
    final adapter = _FakePermissionAdapter(32);

    await CameraPermissionGate(adapter).ensureGranted();

    expect(
      adapter.requested,
      [
        CameraRuntimePermission.bluetoothScan,
        CameraRuntimePermission.bluetoothConnect,
        CameraRuntimePermission.location,
      ],
    );
  });

  test('SDK 29-30 requests foreground location', () async {
    final adapter = _FakePermissionAdapter(30);

    await CameraPermissionGate(adapter).ensureGranted();

    expect(adapter.requested, [CameraRuntimePermission.location]);
  });

  test('denied permission maps to a retry action', () async {
    final adapter = _FakePermissionAdapter(
      34,
      status: CameraPermissionStatus.denied,
    );

    final error = await _capture(
      () => CameraPermissionGate(adapter).ensureGranted(),
    );

    expect(error, isA<CameraPermissionException>());
    expect(
      (error! as CameraPermissionException).repairAction,
      PermissionRepairAction.retryRequest,
    );
  });

  test('permanently denied permission maps to settings', () async {
    final adapter = _FakePermissionAdapter(
      34,
      status: CameraPermissionStatus.permanentlyDenied,
    );

    final error = await _capture(
      () => CameraPermissionGate(adapter).ensureGranted(),
    );

    expect(error, isA<CameraPermissionException>());
    expect(
      (error! as CameraPermissionException).repairAction,
      PermissionRepairAction.openSettings,
    );
  });
}

Future<Object?> _capture(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } catch (error) {
    return error;
  }
}

class _FakePermissionAdapter implements CameraPermissionAdapter {
  _FakePermissionAdapter(
    this.sdkInt, {
    this.status = CameraPermissionStatus.granted,
  });

  final int sdkInt;
  final CameraPermissionStatus status;
  final requested = <CameraRuntimePermission>[];

  @override
  Future<int> androidSdkInt() async => sdkInt;

  @override
  Future<CameraPermissionStatus> request(
    CameraRuntimePermission permission,
  ) async {
    requested.add(permission);
    return status;
  }
}

class _PendingPermissionAdapter implements CameraPermissionAdapter {
  final approval = Completer<CameraPermissionStatus>();
  final requested = <CameraRuntimePermission>[];

  @override
  Future<int> androidSdkInt() async => 34;

  @override
  Future<CameraPermissionStatus> request(CameraRuntimePermission permission) {
    requested.add(permission);
    return approval.future;
  }
}

class _BluetoothDeniedPermissionAdapter implements CameraPermissionAdapter {
  final bluetoothDecision = Completer<CameraPermissionStatus>();
  final requested = <CameraRuntimePermission>[];

  @override
  Future<int> androidSdkInt() async => 34;

  @override
  Future<CameraPermissionStatus> request(CameraRuntimePermission permission) {
    requested.add(permission);
    return permission == CameraRuntimePermission.bluetoothScan
        ? bluetoothDecision.future
        : Future.value(CameraPermissionStatus.granted);
  }
}
