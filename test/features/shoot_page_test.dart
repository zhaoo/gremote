import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/app.dart';
import 'package:gremote/app/app_presence.dart';
import 'package:gremote/app/theme/app_colors.dart';
import 'package:gremote/camera/live/live_view_controller.dart';
import 'package:gremote/camera/sync/camera_state_controller.dart';
import 'package:gremote/features/shoot/widgets/viewfinder.dart';
import 'package:gremote/features/settings/protocol_probe_page.dart';
import 'package:gremote/app/router.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/camera/gateway/fake_camera_model.dart';
import 'package:gremote/camera/gateway/camera_transport.dart';
import 'package:gremote/platform/camera_permission_gate.dart';

import '../support/test_darkroom.dart';

Future<({TestDarkroom env, FakeCameraGateways gateways})> pumpShoot(
  WidgetTester tester, {
  bool connect = false,
  Uint8List? frame,
  FakeCameraModel? camera,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final env = await TestDarkroom.create();
  final gateways = FakeCameraGateways(stepDelay: Duration.zero, camera: camera);
  addTearDown(env.close);
  addTearDown(gateways.dispose);
  appRouter.go('/home');
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...env.overrides,
      if (frame != null)
        liveViewControllerProvider.overrideWith(() => _FixtureLiveView(frame)),
      cameraGatewaysProvider.overrideWithValue(gateways),
      cameraPermissionGateProvider.overrideWithValue(
        CameraPermissionGate(const GrantedCameraPermissionAdapter()),
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
  testWidgets('opening probe ends shoot session and popping reactivates it',
      (tester) async {
    final harness = await pumpShoot(tester, connect: true);
    final container =
        ProviderScope.containerOf(tester.element(find.byTooltip('返回首页')));
    await tester.runAsync(() async {
      await container
          .read(cameraStateControllerProvider.notifier)
          .setParam('WBMode', 'daylight');
    });
    expect(harness.gateways.camera.props['WBMode'], 'daylight');
    await tester.tap(find.byKey(const Key('mode-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('协议探测'));
    await tester.pumpAndSettle();
    expect(find.byType(ProtocolProbePage), findsOneWidget);
    expect(container.read(shootPageVisibleProvider), isFalse);
    expect(harness.gateways.camera.props['WBMode'], 'auto');
    appRouter.pop();
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/shoot');
    expect(container.read(shootPageVisibleProvider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap actual JPEG point sends 25,75 and bars do not focus',
      (tester) async {
    final bytes = File('test/fixtures/live_view_600x400.jpg').readAsBytesSync();
    final harness = await pumpShoot(tester, connect: true, frame: bytes);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    final surface = find.byKey(const Key('live-view-focus-surface'));
    final bounds = tester.getRect(surface);
    final image = liveViewImageRect(bounds.size, const Size(600, 400));
    await tester.tapAt(bounds.topLeft + const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(
        harness.gateways.trace
            .where((path) => path.startsWith('/v1/lens/focus')),
        isEmpty);
    await tester.tapAt(bounds.topLeft +
        image.topLeft +
        Offset(image.width * .25, image.height * .75));
    await tester.pumpAndSettle();
    expect(harness.gateways.trace, contains('/v1/lens/focus?pos=25,75'));
    expect(harness.gateways.camera.files, isEmpty);
    expect(find.byKey(const Key('focus-request-box')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const Key('af-button')), findsNothing);
    final box = tester.widget<DecoratedBox>(find.descendant(
      of: find.byKey(const Key('focus-request-box')),
      matching: find.byType(DecoratedBox),
    ));
    expect(((box.decoration as BoxDecoration).border as Border).top.color,
        GRemoteColors.gold);
  });

  testWidgets('camera options display Chinese and write original wire values',
      (tester) async {
    final harness = await pumpShoot(tester, connect: true);
    expect(find.text('手动曝光'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mode-pro')));
    await tester.pumpAndSettle();
    expect(find.text('白平衡'), findsOneWidget);
    expect(find.text('自动'), findsOneWidget);
    await tester.tap(find.byKey(const Key('param-WBMode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日光'));
    await tester.pumpAndSettle();
    expect(harness.gateways.camera.props['WBMode'], 'daylight');
    final container =
        ProviderScope.containerOf(tester.element(find.byTooltip('返回首页')));
    await tester.tap(find.byTooltip('返回首页'));
    await tester.pumpAndSettle();
    expect(harness.gateways.camera.props['WBMode'], 'auto');
    expect(container.read(shootPageVisibleProvider), isFalse);
    await tester.tap(find.text('拍摄'));
    await tester.pumpAndSettle();
    expect(container.read(shootPageVisibleProvider), isTrue);
  });

  testWidgets(
      'failed focus shows Chinese error and can retry without capturing',
      (tester) async {
    final camera = _FocusRefusalModel();
    final bytes = File('test/fixtures/live_view_600x400.jpg').readAsBytesSync();
    final harness =
        await pumpShoot(tester, connect: true, camera: camera, frame: bytes);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-view-focus-surface')));
    await tester.pumpAndSettle();
    expect(find.text('对焦请求失败，相机可能不支持或已断开连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    camera.refuse = false;
    await tester.tap(find.byKey(const Key('live-view-focus-surface')));
    await tester.pumpAndSettle();
    expect(
        harness.gateways.trace
            .where((path) => path.startsWith('/v1/lens/focus')),
        hasLength(2));
    expect(harness.gateways.camera.files, isEmpty);
  });

  testWidgets('settings translates camera keys and ruler options',
      (tester) async {
    final harness = await pumpShoot(tester, connect: true);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('对焦模式'), findsOneWidget);
    expect(find.text('focusSetting'), findsNothing);
    await tester.tap(find.text('对焦模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动对焦'));
    await tester.pumpAndSettle();
    expect(harness.gateways.camera.props['focusSetting'], 'mf');
  });

  testWidgets('disconnect during held shutter resets gesture before reconnect',
      (tester) async {
    final harness = await pumpShoot(tester, connect: true);
    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('shutter-button'))));
    final controller = container.read(connectionControllerProvider.notifier);
    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('shutter-button'))));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(harness.gateways.trace, contains('operation:1,1'));
    final disconnect = controller.cancel();
    await tester.pumpAndSettle();
    await disconnect;
    await gesture.up();
    await tester.pumpAndSettle();
    final reconnect = controller.connect();
    await tester.pumpAndSettle();
    await reconnect;
    expect(find.byKey(const Key('af-button')), findsNothing);
    await tester.tap(find.byKey(const Key('shutter-button')));
    await tester.pumpAndSettle();
    expect(harness.gateways.camera.files, hasLength(1));
  });

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
    expect(find.byKey(const Key('af-button')), findsNothing);
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

class _FocusRefusalModel extends FakeCameraModel {
  bool refuse = true;

  @override
  CameraResponse handle(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Uint8List? body,
  }) {
    if (refuse && path.startsWith('/v1/lens/focus')) {
      return CameraResponse(
          statusCode: 200,
          headers: const {},
          body: Uint8List.fromList(utf8.encode('{"errCode":400}')));
    }
    return super.handle(method, path, headers: headers, body: body);
  }
}

class _FixtureLiveView extends LiveViewController {
  _FixtureLiveView(this.frame);
  final Uint8List frame;
  @override
  Uint8List? build() => frame;
  @override
  void attach() {}
  @override
  void detach() {}
}
