import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/camera/connection/connection_state.dart';
import 'package:gremote/camera/gateway/ble_gateway.dart';
import 'package:gremote/camera/model/camera_identity.dart';
import 'package:gremote/camera/model/camera_snapshot.dart';
import 'package:gremote/features/home/widgets/connection_card.dart';
import 'package:gremote/features/shoot/widgets/live_view_surface.dart';
import 'package:gremote/features/shoot/widgets/shutter_button.dart';

void main() {
  testWidgets('connection card renders idle and scanning states',
      (tester) async {
    await _pumpCard(tester, const ConnectionIdle());
    expect(find.text('连接 GR III'), findsOneWidget);

    await _pumpCard(tester, const ConnectionScanning());
    expect(find.text('正在扫描附近相机'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('manual Wi-Fi is available when BLE is idle or fails',
      (tester) async {
    var opened = 0;
    await _pumpCard(tester, const ConnectionIdle(),
        onManualWifi: () => opened++);
    await tester.tap(find.text('手动连接 Wi-Fi'));
    expect(opened, 1);

    await _pumpCard(
      tester,
      const ConnectionFailed(ConnectionFailure(
        stage: ConnectionStage.pairing,
        code: 'bleTimeout',
        retryable: true,
        userAction: ConnectionUserAction.retry,
        redactedDetail: 'bleTimeout',
      )),
      onManualWifi: () => opened++,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动连接 Wi-Fi'));
    expect(opened, 2);
  });

  testWidgets('connection card explains Wi-Fi system confirmation',
      (tester) async {
    await _pumpCard(tester, const ConnectionWifiRequesting(_snapshot));

    expect(find.textContaining('系统弹窗'), findsOneWidget);
    expect(find.textContaining('允许'), findsWidgets);
  });

  testWidgets('ready state shows camera facts and firmware warning',
      (tester) async {
    await _pumpCard(
      tester,
      const ConnectionReady(snapshot: _snapshot, firmwareWarning: true),
    );

    expect(find.text('RICOH GR III'), findsOneWidget);
    expect(find.text('2.00'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('固件未经真机验证'), findsOneWidget);
    expect(find.text('进入实景遥控'), findsOneWidget);
  });

  testWidgets('Wi-Fi-only connection does not invent firmware or battery',
      (tester) async {
    await _pumpCard(
      tester,
      const ConnectionReady(
        snapshot: CameraSnapshot(
          identity: CameraIdentity(model: 'RICOH GR III', firmware: ''),
          battery: CameraBattery(level: -1, acPowered: false),
        ),
        firmwareWarning: true,
        wifiOnly: true,
      ),
    );

    expect(find.text('未读取'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    expect(find.text('固件未经真机验证'), findsNothing);
  });

  testWidgets('retryable failure exposes one retry action', (tester) async {
    var retried = false;
    await _pumpCard(
      tester,
      const ConnectionFailed(
        ConnectionFailure(
          stage: ConnectionStage.probing,
          code: 'cameraProbeFailed',
          retryable: true,
          userAction: ConnectionUserAction.retry,
          redactedDetail: 'cameraProbeFailed',
        ),
      ),
      onRetry: () => retried = true,
    );

    await tester.tap(find.text('重新连接'));
    expect(retried, isTrue);
  });

  testWidgets('failure offers a visible path to connection diagnostics',
      (tester) async {
    var opened = false;
    await _pumpCard(
      tester,
      const ConnectionFailed(
        ConnectionFailure(
          stage: ConnectionStage.probing,
          code: 'cameraProbeFailed',
          retryable: true,
          userAction: ConnectionUserAction.retry,
          redactedDetail: 'cameraProbeFailed',
        ),
      ),
      onOpenDiagnostics: () => opened = true,
    );

    await tester.tap(find.text('查看连接诊断'));
    expect(opened, isTrue);
  });

  testWidgets('device choice never exposes the full BLE identifier',
      (tester) async {
    await _pumpCard(
      tester,
      const ConnectionDeviceChoice([
        BleDeviceCandidate(
          id: 'AA:BB:CC:DD:EE:FF',
          name: 'RICOH GR III',
          rssi: -40,
        ),
      ]),
    );

    expect(find.textContaining('AA:BB:CC:DD:EE:FF'), findsNothing);
    expect(find.textContaining('secret-password'), findsNothing);
  });

  testWidgets('live view surface renders the newest image', (tester) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: GRemoteTheme.dark,
        home: Scaffold(body: LiveViewSurface(frame: Uint8List.fromList(png))),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('shutter release waits for the press command', (tester) async {
    final pressCompleter = Completer<void>();
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: GRemoteTheme.dark,
        home: Scaffold(
          body: ShutterButton(
            enabled: true,
            onPressed: () async {
              calls.add('press');
              await pressCompleter.future;
            },
            onReleased: () async => calls.add('release'),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('shutter-button'))),
    );
    await gesture.up();
    await tester.pump();
    expect(calls, ['press']);

    pressCompleter.complete();
    await tester.pump();
    expect(calls, ['press', 'release']);
  });

  testWidgets('shutter is disabled until ready and sends press/release',
      (tester) async {
    var presses = 0;
    var releases = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: GRemoteTheme.dark,
        home: Scaffold(
          body: ShutterButton(
            enabled: false,
            onPressed: () async => presses++,
            onReleased: () async => releases++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('shutter-button')));
    expect(presses, 0);
    expect(releases, 0);

    await tester.pumpWidget(
      MaterialApp(
        theme: GRemoteTheme.dark,
        home: Scaffold(
          body: ShutterButton(
            enabled: true,
            onPressed: () async => presses++,
            onReleased: () async => releases++,
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('shutter-button'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(presses, 1);
    expect(releases, 1);
  });
}

const _snapshot = CameraSnapshot(
  identity: CameraIdentity(model: 'RICOH GR III', firmware: '2.00'),
  battery: CameraBattery(level: 80, acPowered: false),
);

Future<void> _pumpCard(
  WidgetTester tester,
  CameraConnectionState state, {
  VoidCallback? onRetry,
  VoidCallback? onOpenDiagnostics,
  VoidCallback? onManualWifi,
}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: GRemoteTheme.dark,
        home: Scaffold(
          body: ConnectionCard(
            state: state,
            onConnect: () {},
            onRetry: onRetry ?? () {},
            onSelectDevice: (_) {},
            onEnterShoot: () {},
            onOpenDiagnostics: onOpenDiagnostics ?? () {},
            onManualWifi: onManualWifi ?? () {},
          ),
        ),
      ),
    );
