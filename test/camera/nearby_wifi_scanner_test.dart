import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/platform/nearby_wifi_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gremote/wifi_scan');
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('denied permission never starts native Wi-Fi scanning', () async {
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      called = true;
      return null;
    });
    final scanner =
        NativeNearbyWifiScanner(requestPermission: () async => false);
    await expectLater(
        scanner.scan(),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'locationPermissionDenied')));
    expect(called, isFalse);
  });

  test('overlapping requests share scan and preserve SSID and cached status',
      () async {
    final permission = Completer<bool>();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      calls++;
      return {
        'fresh': false,
        'networks': [
          {'ssid': ' RICOH_GR_III ', 'rssi': -45}
        ]
      };
    });
    final scanner =
        NativeNearbyWifiScanner(requestPermission: () => permission.future);
    final first = scanner.scan(), second = scanner.scan();
    permission.complete(true);
    final results = await Future.wait([first, second]);
    expect(calls, 1);
    expect(results.first.networks.single.ssid, ' RICOH_GR_III ');
    expect(results.first.fresh, isFalse);
    await scanner.scan();
    expect(calls, 2);
  });
}
