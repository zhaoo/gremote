import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

class NearbyWifi {
  const NearbyWifi({required this.ssid, required this.rssi});
  final String ssid;
  final int rssi;
}

class WifiScanResult {
  const WifiScanResult({required this.networks, this.fresh = true});
  final List<NearbyWifi> networks;
  final bool fresh;
}

abstract interface class NearbyWifiScanner {
  Future<WifiScanResult> scan();
}

class NativeNearbyWifiScanner implements NearbyWifiScanner {
  NativeNearbyWifiScanner({
    MethodChannel channel = const MethodChannel('gremote/wifi_scan'),
    Future<bool> Function()? requestPermission,
  })  : _channel = channel,
        _requestPermission = requestPermission ?? _requestLocation;

  final MethodChannel _channel;
  final Future<bool> Function() _requestPermission;
  Future<WifiScanResult>? _pending;

  static Future<bool> _requestLocation() async {
    const permission = ph.Permission.locationWhenInUse;
    return (await permission.status).isGranted ||
        (await permission.request()).isGranted;
  }

  @override
  Future<WifiScanResult> scan() {
    if (_pending != null) return _pending!;
    late final Future<WifiScanResult> pending;
    pending = _scan().whenComplete(() {
      if (identical(_pending, pending)) _pending = null;
    });
    _pending = pending;
    return pending;
  }

  Future<WifiScanResult> _scan() async {
    if (!await _requestPermission()) {
      throw PlatformException(code: 'locationPermissionDenied');
    }
    final data = await _channel.invokeMapMethod<String, Object?>('scan');
    final entries = data?['networks'];
    if (entries is! List) throw PlatformException(code: 'invalidScanResults');
    return WifiScanResult(networks: [
      for (final entry in entries)
        if (entry is Map && entry['ssid'] is String && entry['rssi'] is num)
          NearbyWifi(
              ssid: entry['ssid'] as String,
              rssi: (entry['rssi'] as num).toInt()),
    ], fresh: data?['fresh'] == true);
  }
}
