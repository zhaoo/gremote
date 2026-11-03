import 'dart:convert';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/app.dart';
import 'package:gremote/app/app_presence.dart';
import 'package:gremote/app/router.dart';
import 'package:gremote/features/darkroom/editor/editor_page.dart';
import 'package:gremote/media/local/media_gateway.dart';

import '../support/fake_media_gateway.dart';
import '../support/test_darkroom.dart';

Future<void> pumpApp(WidgetTester tester, {FakeMediaGateway? gateway}) async {
  appRouter.go('/home');
  final env = await TestDarkroom.create(
      gateway: gateway ?? FakeMediaGateway(mediaAccess: MediaAccess.denied));
  addTearDown(env.close);
  final catalog = await tester.runAsync(() async => CameraFilmCatalog.fromJson(
      jsonDecode(
              await rootBundle.loadString('assets/films/camera-catalog.json'))
          as Map<String, dynamic>));
  await tester.pumpWidget(ProviderScope(overrides: [
    ...env.overrides,
    cameraFilmCatalogProvider.overrideWith((ref) async => catalog!)
  ], child: const GRemoteApp()));
}

void main() {
  testWidgets('edit route passes the explicit immutable LUT query to editor',
      (tester) async {
    await pumpApp(tester);
    final id = 'official:69:default:${'a' * 64}';
    appRouter.go(Uri(path: '/edit/3', queryParameters: {'lut': id}).toString());
    await tester.pumpAndSettle();
    final editor = tester.widget<EditorPage>(find.byType(EditorPage));
    expect(editor.mediaId, 3);
    expect(editor.initialLut, id);
  });

  testWidgets('shows the four-tab shell', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsOneWidget);
    expect(find.image(const AssetImage('assets/images/home_header.jpg')),
        findsOneWidget);
    expect(find.text('拍摄'), findsOneWidget);
    expect(find.text('相册').last, findsOneWidget);
    expect(find.text('相机'), findsOneWidget);
    final positions = ['首页', '相册', '拍摄', '相机']
        .map((label) => tester.getCenter(find.text(label).last).dx)
        .toList();
    expect(positions, orderedEquals([...positions]..sort()));
    expect(find.text('GOOD PHOTOS  A KINDER WORLD'), findsNothing);
    expect(
        find.byWidgetPredicate(
            (w) => w is Image && w.semanticLabel == 'GRemote'),
        findsOneWidget);
    await tester.tap(find.text('拍摄'));
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/shoot');
    expect(
        tester
            .widget<Scaffold>(find.byType(Scaffold).first)
            .bottomNavigationBar,
        isNull);
    expect(find.text('连接相机后显示取景画面'), findsOneWidget);
    await tester.tap(find.text('前往连接'));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (w) => w is Image && w.semanticLabel == 'GRemote'),
        findsOneWidget);
  });

  testWidgets('camera remains the fourth branch and shoot exit is awaited',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('相机').last);
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/camera');
    expect(find.text('胶卷库'), findsOneWidget);
    expect(
        tester
            .widget<GRemoteShell>(find.byType(GRemoteShell))
            .navigationShell
            .currentIndex,
        3);
    await tester.tap(find.text('拍摄').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<GRemoteShell>(find.byType(GRemoteShell))
            .navigationShell
            .currentIndex,
        2);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(GRemoteShell)));
    final finishShootSession = container.read(shootExitHandlerProvider)!;
    var exits = 0;
    container.read(shootExitHandlerProvider.notifier).state = () async {
      exits++;
      return false;
    };
    appRouter.go('/camera');
    await tester.pumpAndSettle();
    expect(exits, 1);
    expect(appRouter.routeInformationProvider.value.uri.path, '/shoot');
    container.read(shootExitHandlerProvider.notifier).state = () async {
      exits++;
      return finishShootSession();
    };
    appRouter.go('/camera');
    await tester.pumpAndSettle();
    expect(exits, 2);
    expect(appRouter.routeInformationProvider.value.uri.path, '/camera');
    expect(find.text('首页'), findsOneWidget);
    expect(container.read(shootPageVisibleProvider), isFalse);
  });

  testWidgets('unfinished sections explain their availability', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('相册').last);
    await tester.pumpAndSettle();
    expect(find.text('允许访问照片'), findsOneWidget);

    await tester.tap(find.text('相机').last);
    await tester.pumpAndSettle();
    expect(find.text('胶卷库'), findsOneWidget);
    expect(find.text('扩展'), findsOneWidget);
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
    await tester.tap(find.text('相册').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('media-3')));
    await tester.pumpAndSettle();
    expect(find.text('R003.JPG'), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-tool-grid')), findsOneWidget);
    expect(find.text('GOOD PHOTOS  A KINDER WORLD'), findsNothing,
        reason: 'the editor covers the tab shell');
    await tester.tap(find.byTooltip('返回相册'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
  });
}
