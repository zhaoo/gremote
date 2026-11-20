import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/camera/gateway/ble_gateway.dart';
import 'package:gremote/features/home/widgets/camera_switcher.dart';

void main() {
  testWidgets(
      'scan shows devices without support explanations and returns selection',
      (tester) async {
    const candidate = BleDeviceCandidate(
        id: 'test-device', name: 'RICOH GR IV Monochrome', rssi: -45);
    BleDeviceCandidate? selected;
    await tester.pumpWidget(MaterialApp(
        theme: GRemoteTheme.light,
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async => selected =
                        await showModalBottomSheet<BleDeviceCandidate>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => CameraSwitcher(
                                discover: () async => [candidate],
                                onManualWifi: () {})),
                    child: const Text('打开'))))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('GR IV Monochrome'), findsOneWidget);
    expect(find.textContaining('自动识别'), findsNothing);
    expect(find.textContaining('M10V'), findsNothing);
    await tester.tap(find.text('GR IV Monochrome'));
    await tester.pumpAndSettle();
    expect(selected, same(candidate));
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed discovery ignores late results', (tester) async {
    final scan = Completer<List<BleDeviceCandidate>>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CameraSwitcher(
                discover: () => scan.future, onManualWifi: () {}))));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    scan.complete([]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty scan offers refresh and manual Wi-Fi on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: GRemoteTheme.dark,
        home: Scaffold(
            body: CameraSwitcher(
                discover: () async => [], onManualWifi: () {}))));
    await tester.pumpAndSettle();
    expect(find.text('未发现相机'), findsOneWidget);
    expect(find.byTooltip('重新扫描'), findsOneWidget);
    expect(find.text('手动连接 Wi-Fi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
