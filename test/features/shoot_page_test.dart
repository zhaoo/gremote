import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show SemanticsFlag;

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
import '../support/echo_camera_model.dart';

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
    await tester.tap(find.text('连接相机'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入拍摄'));
  } else {
    await tester.tap(find.text('拍摄'));
  }
  await tester.pumpAndSettle();
  return (env: env, gateways: gateways);
}

void main() {
  testWidgets(
      'aperture row and ruler follow HTTP readback without socket events',
      (tester) async {
    await pumpShoot(tester, connect: true, camera: EchoCameraModel());
    await tester.tap(find.byKey(const Key('param-av')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byKey(const Key('ruler')), matching: find.text('4.0')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const Key('param-av')), matching: find.text('4.0')),
        findsOneWidget);
    final selected = tester.widget<Text>(find.descendant(
        of: find.byKey(const Key('ruler')), matching: find.text('4.0')));
    expect(selected.style!.fontWeight, FontWeight.w700);
  });

  testWidgets(
      'shoot toolbar omits model name and groups controls at trailing edge',
      (tester) async {
    await pumpShoot(tester, size: const Size(320, 720));

    Rect buttonRect(String tooltip) => tester.getRect(find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip));
    final recipe = buttonRect('组合方案');
    final settings = buttonRect('设置');
    expect(find.text('GR III'), findsNothing);
    expect(recipe.width, greaterThanOrEqualTo(44));
    expect(settings.width, greaterThanOrEqualTo(44));
    expect(settings.left - recipe.right, closeTo(0, 1));
    expect(320 - settings.right, inInclusiveRange(0, 12));
  });

  testWidgets('shoot settings switch and explicit timer keep current readback',
      (tester) async {
    final harness = await pumpShoot(tester, connect: true);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('拍摄'), findsOneWidget);
    expect(find.text('相机'), findsOneWidget);
    final histogram = find.byKey(const Key('settings-histogram'));
    expect(tester.widget<Switch>(histogram).value, false);
    await tester.tap(histogram);
    await tester.pump();
    expect(tester.widget<Switch>(histogram).value, true);
    expect(find.text('拍摄设置'), findsOneWidget);
    await tester.tap(find.text('定时拍摄'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timer-self10s')));
    await tester.pumpAndSettle();
    expect(harness.gateways.camera.props['shootMode'], 'self10s');
    expect(find.text('10 秒'), findsOneWidget);
    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('settings-histogram'))));
    harness.gateways.camera.props['shootMode'] = 'self2s';
    final refresh =
        container.read(cameraStateControllerProvider.notifier).refresh();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await refresh;
    expect(find.text('2 秒'), findsOneWidget);
    expect(find.text('照片格式'), findsOneWidget);
    expect(find.text('对焦模式'), findsOneWidget);
    expect(find.text('其他参数'), findsNothing);
    expect(find.text('测光渐变延时（实验）'), findsNothing);
    await tester.tap(find.byTooltip('关闭拍摄设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(histogram).value, true);
    // Leave no periodic histogram timer alive after the test.
    await tester.tap(histogram);
    await tester.pump();
  });

  testWidgets(
      'settings omit unknown raw fields and keep labelled extras secondary',
      (tester) async {
    final camera = FakeCameraModel();
    camera.props['mysteryParameter'] = '6';
    camera.props['mysteryParameterList'] = ['6', '7'];
    await pumpShoot(tester, connect: true, camera: camera);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('其他参数'), findsNothing);
    expect(find.text('6'), findsNothing);
    expect(find.text('降噪'), findsNothing);
    await tester.ensureVisible(find.text('更多参数'));
    await tester.tap(find.text('更多参数'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('降噪'));
    await tester.tap(find.text('降噪'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('低'));
    await tester.pumpAndSettle();
    expect(camera.props['noiseReduction'], 'low');
  });

  testWidgets('secondary drive selector retains non-timer camera wire options',
      (tester) async {
    final camera = FakeCameraModel();
    camera.props['shootModeList'] = [
      'single',
      'self2s',
      'self10s',
      'continuousH'
    ];
    await pumpShoot(tester, connect: true, camera: camera);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('更多参数'));
    await tester.tap(find.text('更多参数'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('驱动模式'));
    await tester.tap(find.text('驱动模式'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ruler')), findsOneWidget);
    await tester.ensureVisible(find.text('高速连拍'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('高速连拍'));
    await tester.pumpAndSettle();
    expect(camera.props['shootMode'], 'continuousH');
    expect(camera.files, isEmpty);
  });

  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    testWidgets('settings remain reachable with large text at $size',
        (tester) async {
      tester.binding.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpShoot(tester, connect: true);
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('机内胶卷'));
      expect(find.text('机内胶卷').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('定时拍摄'));
      await tester.tap(find.text('定时拍摄'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('timer-self2s')));
      expect(
          find.byKey(const Key('timer-self2s')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion expands settings without a forced transition',
      (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpShoot(tester, connect: true);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('更多参数'));
    await tester.tap(find.text('更多参数'));
    await tester.pump();
    expect(find.text('降噪').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timer choices respect camera supported values', (tester) async {
    final camera = FakeCameraModel();
    camera.props['shootMode'] = 'continuous';
    camera.props['shootModeList'] = ['single', 'self10s', 'continuous'];
    await pumpShoot(tester, connect: true, camera: camera);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('连续'), findsOneWidget);
    await tester.tap(find.text('定时拍摄'));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.byKey(const Key('timer-self2s'))).onTap,
        isNull);
    await tester.tap(find.byKey(const Key('timer-single')));
    await tester.pumpAndSettle();
    expect(camera.props['shootMode'], 'single');
    expect(find.text('关闭'), findsOneWidget);
  });

  testWidgets('held shutter releases once after rotating the workspace',
      (tester) async {
    final harness = await pumpShoot(tester, connect: true);
    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('shutter-button'))));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(harness.gateways.trace, contains('operation:1,1'));
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(harness.gateways.trace.where((s) => s == 'operation:2,1'),
        hasLength(1));
    expect(harness.gateways.camera.files, hasLength(1));
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('af-button')))
            .onPressed,
        isNotNull);
  });

  testWidgets('aspect selection stays current while settings remain open',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final harness = await pumpShoot(tester, connect: true);
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('aspect-1:1')));
      await tester.pumpAndSettle();
      expect(harness.gateways.camera.props['aspectRatio'], '1:1');
      expect(
          tester
              .getSemantics(find.byKey(const Key('aspect-1:1')))
              .hasFlag(SemanticsFlag.isSelected),
          isTrue);
      final container = ProviderScope.containerOf(
          tester.element(find.byKey(const Key('aspect-1:1'))));
      harness.gateways.camera.props['aspectRatio'] = '3:2';
      final refresh =
          container.read(cameraStateControllerProvider.notifier).refresh();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await refresh;
      await tester.pumpAndSettle();
      expect(
          tester
              .getSemantics(find.byKey(const Key('aspect-3:2')))
              .hasFlag(SemanticsFlag.isSelected),
          isTrue);
      expect(
          tester
              .getSemantics(find.byKey(const Key('aspect-1:1')))
              .hasFlag(SemanticsFlag.isSelected),
          isFalse);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('landscape keeps full preview beside reachable capture controls',
      (tester) async {
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
    final bytes = File('test/fixtures/live_view_600x400.jpg').readAsBytesSync();
    await pumpShoot(tester, connect: true, frame: bytes);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    final preview =
        tester.getRect(find.byKey(const Key('live-view-focus-surface')));
    final shutter = tester.getRect(find.byKey(const Key('shutter-button')));
    expect(preview.width, greaterThan(500));
    expect(preview.right, lessThanOrEqualTo(shutter.left));
    await tester.tap(find.byKey(const Key('mode-pro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('param-sv')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('shutter-button')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('independent AF focuses without creating a photo',
      (tester) async {
    final harness = await pumpShoot(tester, connect: true);
    await tester.tap(find.byKey(const Key('af-button')));
    await tester.pumpAndSettle();
    expect(harness.gateways.trace, contains('/v1/lens/focus?pos=50,50'));
    expect(harness.gateways.camera.files, isEmpty);
    await tester.tap(find.byKey(const Key('shutter-button')));
    await tester.pumpAndSettle();
    expect(harness.gateways.camera.files, hasLength(1));
  });
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
    expect(find.byKey(const Key('af-button')), findsOneWidget);
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
    expect(
        find.descendant(
            of: find.widgetWithText(ListTile, '定时拍摄'),
            matching: find.text('关闭')),
        findsOneWidget);
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
    expect(find.byKey(const Key('af-button')), findsOneWidget);
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
