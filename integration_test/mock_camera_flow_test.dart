import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gremote/app/app.dart';
import 'package:gremote/app/router.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/camera/live/live_view_controller.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/platform/camera_permission_gate.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fake camera connects, previews, shoots, and stays ready',
      (tester) async {
    final path = '${await getDatabasesPath()}/gremote-integration-'
        '${DateTime.now().microsecondsSinceEpoch}.db';
    final db = await GRemoteDatabase.open(path: path);
    addTearDown(() async {
      await db.close();
      await deleteDatabase(path);
    });
    final gateways = FakeCameraGateways(stepDelay: Duration.zero);
    addTearDown(gateways.dispose);
    appRouter.go('/home');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        cameraGatewaysProvider.overrideWithValue(gateways),
        cameraPermissionGateProvider.overrideWithValue(
          CameraPermissionGate(const GrantedCameraPermissionAdapter()),
        ),
      ],
      child: const GRemoteApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('连接 GR III'));
    await tester.pumpAndSettle();
    expect(find.text('已连接'), findsOneWidget);

    await tester.tap(find.text('进入实景遥控'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
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
    await tester.pump(const Duration(milliseconds: 400));
    expect(gateways.camera.files, hasLength(1));

    appRouter.go('/home');
    await tester.pumpAndSettle();
    expect(find.text('已连接'), findsOneWidget);
  });
}
