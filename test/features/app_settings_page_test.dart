import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/app.dart';
import 'package:gremote/app/interaction/app_haptics.dart';
import 'package:gremote/app/router.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/features/settings/app_settings_page.dart';
import 'package:gremote/settings/app_preferences.dart';
import 'package:gremote/settings/preferences_controller.dart';
import 'package:gremote/settings/preferences_repository.dart';
import '../support/test_darkroom.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('gremote/app_info'),
            (call) async {
      if (call.method != 'read') {
        throw StateError('unexpected app info request');
      }
      return {
        'appName': 'GRemote',
        'version': '1.2.0-test',
        'buildNumber': '37'
      };
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('gremote/app_info'), null));

  testWidgets(
      'home menu preserves connection entries and opens standalone settings',
      (tester) async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    appRouter.go('/home');
    await tester.pumpWidget(
        ProviderScope(overrides: env.overrides, child: const GRemoteApp()));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(GRemoteApp)));
    final connection = container.read(connectionControllerProvider.notifier);
    final before = container.read(connectionControllerProvider);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('手动连接 Wi-Fi'), findsWidgets);
    expect(find.text('诊断信息'), findsOneWidget);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(AppSettingsPage), findsOneWidget);
    expect(find.text('首页'), findsNothing);
    expect(find.text('1.2.0-test (37)'), findsOneWidget);
    expect(container.read(connectionControllerProvider.notifier),
        same(connection));
    expect(container.read(connectionControllerProvider), same(before));
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(container.read(connectionControllerProvider), same(before));
  });

  testWidgets(
      'three themes, haptics and licenses remain usable on a small screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 736);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    appRouter.go('/settings');
    await tester.pumpWidget(
        ProviderScope(overrides: env.overrides, child: const GRemoteApp()));
    await tester.pumpAndSettle();
    for (final (label, value) in [
      ('浅色', ThemePreference.light),
      ('跟随系统', ThemePreference.system),
      ('深色', ThemePreference.dark)
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect((await PreferencesRepository(env.db).load()).theme, value);
      expect(find.bySemanticsLabel('$label，已选择'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect((await PreferencesRepository(env.db).load()).haptics, isFalse);
    await tester.ensureVisible(find.text('开源许可'));
    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed preference save stays visible until a successful retry',
      (tester) async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    appRouter.go('/settings');
    await tester.pumpWidget(
        ProviderScope(overrides: env.overrides, child: const GRemoteApp()));
    await tester.pumpAndSettle();
    await env.db.execute(
        "CREATE TRIGGER reject_settings BEFORE INSERT ON app_kv WHEN NEW.key LIKE 'settings.%' BEGIN SELECT RAISE(ABORT, 'disk unavailable'); END");
    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(find.text('设置未保存，请重试'), findsOneWidget);
    expect((await PreferencesRepository(env.db).load()).theme,
        ThemePreference.dark);
    await env.db.execute('DROP TRIGGER reject_settings');
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('设置未保存，请重试'), findsNothing);
    expect((await PreferencesRepository(env.db).load()).theme,
        ThemePreference.light);
  });

  test('haptic preference gates actual platform feedback', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <String>[];
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String);
      }
      return null;
    });
    addTearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    final container = ProviderContainer(overrides: env.overrides);
    addTearDown(container.dispose);
    final haptics = container.read(appHapticsProvider);
    await haptics.selection();
    expect(calls, ['HapticFeedbackType.selectionClick']);
    await container.read(appPreferencesProvider.notifier).setHaptics(false);
    await haptics.selection();
    expect(calls.length, 1);
  });
}
