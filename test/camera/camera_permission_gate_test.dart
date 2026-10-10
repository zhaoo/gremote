import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/platform/camera_permission_gate.dart';

void main() {
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
