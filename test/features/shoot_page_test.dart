import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/app.dart';
import 'package:gremote/app/router.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/platform/camera_permission_gate.dart';

import '../support/test_darkroom.dart';

Future<({TestDarkroom env, FakeCameraGateways gateways})> pumpShoot(
  WidgetTester tester, {
  bool connect = false,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final env = await TestDarkroom.create();
  final gateways = FakeCameraGateways(stepDelay: Duration.zero);
  addTearDown(env.close);
  addTearDown(gateways.dispose);
  appRouter.go('/home');
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...env.overrides,
      cameraGatewaysProvider.overrideWithValue(gateways),
      cameraPermissionGateProvider.overrideWithValue(
        const CameraPermissionGate(GrantedCameraPermissionAdapter()),
      ),
    ],
    child: const GRemoteApp(),
  ));
  await tester.pumpAndSettle();
  if (connect) {
    await tester.tap(find.text('连接 GR III'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入实景遥控'));
  } else {
    await tester.tap(find.text('拍摄'));
  }
  await tester.pumpAndSettle();
  return (env: env, gateways: gateways);
}

void main() {
  testWidgets('shoot branch is full screen with Xiaomi-style mode carousel',
      (tester) async {
    await pumpShoot(tester);

    expect(find.text('首页'), findsNothing);
    expect(find.text('更多'), findsOneWidget);
    expect(find.text('延时'), findsOneWidget);
    expect(find.text('包围'), findsOneWidget);
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('专业'), findsOneWidget);
    expect(find.byKey(const Key('shutter-button')), findsOneWidget);
    expect(find.byKey(const Key('af-button')), findsOneWidget);
    expect(find.text('前往连接'), findsOneWidget);
  });

  testWidgets('professional mode exposes camera parameters and ruler',
      (tester) async {
    await pumpShoot(tester, connect: true);

    await tester.tap(find.byKey(const Key('mode-pro')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('param-sv')), findsOneWidget);
    expect(find.byKey(const Key('param-tv')), findsOneWidget);

    await tester.tap(find.byKey(const Key('param-sv')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ruler')), findsOneWidget);
    expect(find.text('400'), findsWidgets);
  });

  testWidgets('compact portrait and large text do not overflow',
      (tester) async {
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpShoot(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
  });
}
