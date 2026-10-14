import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/features/home/widgets/manual_wifi_dialog.dart';
import 'package:gremote/platform/nearby_wifi_scanner.dart';

class _Scanner implements NearbyWifiScanner {
  int requests = 0;
  String? failure;
  @override
  Future<WifiScanResult> scan() async {
    requests++;
    if (failure != null) throw PlatformException(code: failure!);
    return const WifiScanResult(networks: [
      NearbyWifi(ssid: 'RICOH_GR_III', rssi: -45),
      NearbyWifi(ssid: 'RICOH_GR_OTHER', rssi: -60),
    ]);
  }
}

void main() {
  testWidgets('scan permission failure still allows manual connection',
      (tester) async {
    final scanner = _Scanner()..failure = 'locationPermissionDenied';
    (String, String)? result;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      result = await showDialog<(String, String)>(
                          context: context,
                          builder: (_) => ManualWifiDialog(scanner: scanner));
                    },
                    child: const Text('打开'))))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫描附近 Wi-Fi'));
    await tester.pumpAndSettle();
    expect(find.text('打开系统设置'), findsOneWidget);
    await tester.tap(find.text('手动输入网络名称'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'RICOH_GR_III');
    await tester.enterText(find.byType(TextField).last, '12345678');
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(result, ('RICOH_GR_III', '12345678'));
  });

  testWidgets('selecting a scanned network needs only its password',
      (tester) async {
    final scanner = _Scanner();
    (String, String)? result;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      result = await showDialog<(String, String)>(
                          context: context,
                          builder: (_) => ManualWifiDialog(scanner: scanner));
                    },
                    child: const Text('打开'))))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫描附近 Wi-Fi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RICOH_GR_III'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '12345678');
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(result, ('RICOH_GR_III', '12345678'));
    expect(scanner.requests, 1);
  });

  testWidgets('submitting credentials closes the dialog without stale fields',
      (tester) async {
    (String, String)? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<(String, String)>(
                      context: context,
                      builder: (_) => const ManualWifiDialog(),
                    );
                  },
                  child: const Text('打开'),
                )),
      ),
    ));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动输入网络名称'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, ' GR_TEST ');
    await tester.enterText(find.byType(TextField).last, '12345678');
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect(result, (' GR_TEST ', '12345678'));
    expect(tester.takeException(), isNull);
  });
}
