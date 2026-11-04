import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/app.dart';
import 'package:gremote/app/router.dart';
import 'package:gremote/app/theme/app_palette.dart';
import 'package:gremote/features/settings/app_settings_page.dart';
import 'package:gremote/location/location_controls.dart';
import 'package:gremote/settings/app_preferences.dart';
import 'package:gremote/settings/preferences_controller.dart';
import 'package:gremote/settings/preferences_repository.dart';
import '../support/test_darkroom.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/features/darkroom/editor/widgets/curve_panel.dart';
import 'package:gremote/darkroom/model/photo_edits.dart';

class ReadFailsOnce extends PreferencesRepository {
  ReadFailsOnce(super.db);
  bool first = true;
  @override
  Future<AppPreferences> load() async {
    if (first) {
      first = false;
      throw StateError('temporary read failure');
    }
    return super.load();
  }
}

void main() {
  testWidgets('read failure then theme selection preserves persisted haptics',
      (tester) async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    await PreferencesRepository(env.db).save(
        const AppPreferences(theme: ThemePreference.light, haptics: false));
    final repo = ReadFailsOnce(env.db);
    final controller = AppPreferencesController(repo, await repo.hydrate());
    addTearDown(controller.dispose);
    await controller.setTheme(ThemePreference.system);
    expect((await repo.load()).haptics, false);
  });
  testWidgets('open real location sheet follows theme including background',
      (tester) async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    appRouter.go('/home');
    await tester.pumpWidget(
        ProviderScope(overrides: env.overrides, child: const GRemoteApp()));
    await tester.pumpAndSettle();
    final controller =
        ProviderScope.containerOf(tester.element(find.byType(GRemoteApp)))
            .read(appPreferencesProvider.notifier);
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue);
    await controller.setTheme(ThemePreference.system);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('位置记录'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('位置记录'));
    await tester.pumpAndSettle();
    expect(find.byType(LocationControls), findsOneWidget);
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpAndSettle();
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(Theme.of(tester.element(find.byType(LocationControls))).brightness,
        Brightness.light);
    final sheetContext = tester.element(find.byType(BottomSheet));
    expect(
        sheet.backgroundColor ??
            Theme.of(sheetContext).bottomSheetTheme.backgroundColor,
        AppPalette.light.raised);
  });
  testWidgets('disabled haptics suppresses actual settings tooltip feedback',
      (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add('${call.arguments}');
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('gremote/app_info'),
        (call) async =>
            {'appName': 'GRemote', 'version': '1', 'buildNumber': '1'});
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('gremote/app_info'), null));
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    appRouter.go('/settings');
    await tester.pumpWidget(
        ProviderScope(overrides: env.overrides, child: const GRemoteApp()));
    await tester.pumpAndSettle();
    final controller =
        ProviderScope.containerOf(tester.element(find.byType(AppSettingsPage)))
            .read(appPreferencesProvider.notifier);
    await controller.setHaptics(false);
    await tester.pumpAndSettle();
    calls.clear();
    await tester.longPress(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });
  testWidgets(
      'switch drag uses only the explicit enabled feedback on both platforms',
      (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('gremote/app_info'),
        (call) async =>
            {'appName': 'GRemote', 'version': '1', 'buildNumber': '1'});
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('gremote/app_info'), null));
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    appRouter.go('/settings');
    await tester.pumpWidget(ProviderScope(overrides: [
      ...env.overrides,
      initialPreferencesProvider.overrideWithValue(
          const PreferencesState(preferences: AppPreferences(haptics: false))),
    ], child: const GRemoteApp()));
    await tester.pumpAndSettle();
    calls.clear();
    await tester.drag(find.byType(Switch), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('HapticFeedbackType.lightImpact')));
    expect(
        calls.where((v) => v != 'HapticFeedbackType.selectionClick'), isEmpty);
  },
      variant: const TargetPlatformVariant(
          {TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets('light RGB channel labels have readable contrast',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: GRemoteTheme.light,
        home: Scaffold(
            body: CurvePanel(
                edits: const PhotoEdits(),
                onChanged: (_) {},
                onStart: () {},
                onEnd: () {}))));
    final background = GRemoteTheme.light.scaffoldBackgroundColor;
    for (final name in ['红色', '绿色', '蓝色']) {
      Color foreground() => tester.widget<Text>(find.text(name)).style!.color!;
      expect(contrast(foreground(), background), greaterThanOrEqualTo(4.5),
          reason: name);
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(contrast(foreground(), background), greaterThanOrEqualTo(4.5),
          reason: 'selected $name');
    }
  });
}

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}
