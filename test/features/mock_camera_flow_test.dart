import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/app.dart';
import 'package:gremote/app/router.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/camera/live/live_view_controller.dart';
import 'package:gremote/platform/camera_permission_gate.dart';

import '../support/test_darkroom.dart';

void main() {
  testWidgets('fake camera completes the visible connect and shoot flow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateways = FakeCameraGateways(stepDelay: Duration.zero);
    final env = await TestDarkroom.create();
    addTearDown(gateways.dispose);
    addTearDown(env.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...env.overrides,
          cameraGatewaysProvider.overrideWithValue(gateways),
          cameraPermissionGateProvider.overrideWithValue(
            CameraPermissionGate(const GrantedCameraPermissionAdapter()),
          ),
        ],
        child: const GRemoteApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('连接 GR III'));
    await tester.pumpAndSettle();
    expect(find.text('已连接'), findsOneWidget);

    await tester.tap(find.text('进入实景遥控'));
    await tester.pumpAndSettle();
    final context =
        tester.element(find.byKey(const Key('live-view-focus-surface')));
    final frame =
        ProviderScope.containerOf(context).read(liveViewControllerProvider);
    expect(frame, isNotNull);
    await tester.runAsync(() => precacheImage(MemoryImage(frame!), context));
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsOneWidget);

    final shutter = find.byKey(const Key('shutter-button'));
    final gesture = await tester.startGesture(tester.getCenter(shutter));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(gateways.trace, containsAll(['operation:1,1', 'operation:2,1']));

    appRouter.go('/home');
    await tester.pumpAndSettle();
    expect(find.text('已连接'), findsOneWidget);
  });
}
