import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/app.dart';
import 'package:gremote/app/router.dart';
import 'package:gremote/media/local/media_gateway.dart';

import '../support/fake_media_gateway.dart';
import '../support/test_darkroom.dart';

Future<void> pumpApp(WidgetTester tester, {FakeMediaGateway? gateway}) async {
  appRouter.go('/home');
  final env = await TestDarkroom.create(
      gateway: gateway ?? FakeMediaGateway(mediaAccess: MediaAccess.denied));
  addTearDown(env.close);
  await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const GRemoteApp()));
}

void main() {
  testWidgets('shows the four-tab shell', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('拍摄'), findsOneWidget);
    expect(find.text('图库'), findsOneWidget);
    expect(find.text('暗房'), findsOneWidget);
    expect(find.text('走上街头'), findsOneWidget);
    await tester.tap(find.text('拍摄'));
    await tester.pumpAndSettle();
    expect(find.text('连接相机后显示取景画面'), findsOneWidget);
    await tester.tap(find.text('前往连接'));
    await tester.pumpAndSettle();
    expect(find.text('走上街头'), findsOneWidget);
  });

  testWidgets('unfinished sections explain their availability', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('图库'));
    await tester.pumpAndSettle();
    expect(find.text('允许访问照片'), findsOneWidget);

    await tester.tap(find.text('暗房'));
    await tester.pumpAndSettle();
    expect(find.text('LUT 库'), findsOneWidget);
    expect(find.text('出图方案'), findsOneWidget);
  });

  testWidgets('shoot controls fit a compact portrait display', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('拍摄'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('前往连接'), findsOneWidget);
  });

  testWidgets('connection shortcut restores portrait orientation',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final orientations = <List<dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(call.arguments as List<dynamic>);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('拍摄'));
    await tester.pumpAndSettle();
    orientations.clear();
    await tester.tap(find.text('前往连接'));
    await tester.pumpAndSettle();
    expect(orientations, contains(equals(['DeviceOrientation.portraitUp'])));
  });

  testWidgets('library photos open the full-screen editor', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester,
        gateway:
            FakeMediaGateway(entries: [mediaEntry(3)], exif: {3: grMeta()}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图库'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('media-3')));
    await tester.pumpAndSettle();
    expect(find.text('R003.JPG'), findsOneWidget);
    expect(find.text('存为方案'), findsOneWidget);
    expect(find.text('GOOD PHOTOS  A KINDER WORLD'), findsNothing,
        reason: 'the editor covers the tab shell');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
  });
}
