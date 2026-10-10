import 'package:permission_handler/permission_handler.dart' as ph;

import 'device_api.g.dart';

enum CameraRuntimePermission {
  bluetoothScan,
  bluetoothConnect,
  nearbyWifi,
  location,
}

enum CameraPermissionStatus { granted, denied, permanentlyDenied }

enum PermissionRepairAction { retryRequest, openSettings }

abstract interface class CameraPermissionAdapter {
  Future<int> androidSdkInt();

  Future<CameraPermissionStatus> request(CameraRuntimePermission permission);
}

class CameraPermissionException implements Exception {
  const CameraPermissionException({
    required this.code,
    required this.permission,
    required this.repairAction,
  });

  final String code;
  final CameraRuntimePermission permission;
  final PermissionRepairAction repairAction;

  @override
  String toString() => 'CameraPermissionException('
      'code: $code, permission: ${permission.name}, '
      'repairAction: ${repairAction.name})';
}

class CameraPermissionGate {
  const CameraPermissionGate(this._adapter);

  final CameraPermissionAdapter _adapter;

  Future<void> ensureGranted() async {
    final sdk = await _adapter.androidSdkInt();
    for (final permission in _requiredPermissions(sdk)) {
      final status = await _adapter.request(permission);
      switch (status) {
        case CameraPermissionStatus.granted:
          break;
        case CameraPermissionStatus.denied:
          throw CameraPermissionException(
            code: 'permissionDenied',
            permission: permission,
            repairAction: PermissionRepairAction.retryRequest,
          );
        case CameraPermissionStatus.permanentlyDenied:
          throw CameraPermissionException(
            code: 'permissionPermanentlyDenied',
            permission: permission,
            repairAction: PermissionRepairAction.openSettings,
          );
      }
    }
  }

  Future<void> ensureWifiGranted() async {
    final sdk = await _adapter.androidSdkInt();
    final permission = sdk >= 33
        ? CameraRuntimePermission.nearbyWifi
        : CameraRuntimePermission.location;
    final status = await _adapter.request(permission);
    if (status != CameraPermissionStatus.granted) {
      throw CameraPermissionException(
        code: status == CameraPermissionStatus.permanentlyDenied
            ? 'permissionPermanentlyDenied'
            : 'permissionDenied',
        permission: permission,
        repairAction: status == CameraPermissionStatus.permanentlyDenied
            ? PermissionRepairAction.openSettings
            : PermissionRepairAction.retryRequest,
      );
    }
  }

  List<CameraRuntimePermission> _requiredPermissions(int sdk) {
    if (sdk >= 33) {
      return const [
        CameraRuntimePermission.bluetoothScan,
        CameraRuntimePermission.bluetoothConnect,
        CameraRuntimePermission.nearbyWifi,
      ];
    }
    if (sdk >= 31) {
      return const [
        CameraRuntimePermission.bluetoothScan,
        CameraRuntimePermission.bluetoothConnect,
        CameraRuntimePermission.location,
      ];
    }
    return const [CameraRuntimePermission.location];
  }
}

class PermissionHandlerCameraPermissionAdapter
    implements CameraPermissionAdapter {
  PermissionHandlerCameraPermissionAdapter({CameraDeviceHostApi? hostApi})
      : _hostApi = hostApi ?? CameraDeviceHostApi();

  final CameraDeviceHostApi _hostApi;

  @override
  Future<int> androidSdkInt() => _hostApi.androidSdkInt();

  @override
  Future<CameraPermissionStatus> request(
    CameraRuntimePermission permission,
  ) async {
    final status = await _toPermission(permission).request();
    if (status.isGranted || status.isLimited) {
      return CameraPermissionStatus.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraPermissionStatus.permanentlyDenied;
    }
    return CameraPermissionStatus.denied;
  }

  ph.Permission _toPermission(CameraRuntimePermission permission) =>
      switch (permission) {
        CameraRuntimePermission.bluetoothScan => ph.Permission.bluetoothScan,
        CameraRuntimePermission.bluetoothConnect =>
          ph.Permission.bluetoothConnect,
        CameraRuntimePermission.nearbyWifi => ph.Permission.nearbyWifiDevices,
        CameraRuntimePermission.location => ph.Permission.locationWhenInUse,
      };
}

class GrantedCameraPermissionAdapter implements CameraPermissionAdapter {
  const GrantedCameraPermissionAdapter({this.sdkInt = 34});

  final int sdkInt;

  @override
  Future<int> androidSdkInt() async => sdkInt;

  @override
  Future<CameraPermissionStatus> request(
    CameraRuntimePermission permission,
  ) async =>
      CameraPermissionStatus.granted;
}
