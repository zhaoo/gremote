import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/features/home/home_page.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/platform/camera_permission_gate.dart';
import '../../support/test_darkroom.dart';

void main() {
  for (final (width, scale) in [(390.0, 1.0), (320.0, 1.6)]) {
    testWidgets(
        'home connection and controls remain reachable at $width with text $scale',
        (t) async {
      t.view.physicalSize = Size(width, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final env = await TestDarkroom.create();
      addTearDown(env.close);
      final gateway = FakeCameraGateways(stepDelay: Duration.zero);
      addTearDown(gateway.dispose);
      await t.pumpWidget(ProviderScope(
          overrides: [
            ...env.overrides,
            cameraGatewaysProvider.overrideWithValue(gateway),
            cameraPermissionGateProvider.overrideWithValue(
                CameraPermissionGate(const GrantedCameraPermissionAdapter()))
          ],
          child: MaterialApp(
              theme: GRemoteTheme.dark,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const Scaffold(body: HomePage()))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('连接相机'));
      await t.tap(find.text('连接相机'));
      await t.pumpAndSettle();
      expect(find.text('已连接'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('进入拍摄'));
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('位置记录'));
      expect(t.takeException(), isNull);
    });
  }
}
