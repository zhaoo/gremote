import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/app.dart';
import 'package:gremote/app/router.dart';
import 'package:gremote/app/theme/app_palette.dart';
import 'package:gremote/features/home/home_page.dart';
import 'package:gremote/settings/app_preferences.dart';
import 'package:gremote/settings/preferences_controller.dart';
import '../support/test_darkroom.dart';

void main() {
  testWidgets(
      'explicit appearance overrides the system; system mode follows live changes',
      (tester) async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue);
    appRouter.go('/home');
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpWidget(
        ProviderScope(overrides: env.overrides, child: const GRemoteApp()));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(HomePage));
    final controller = ProviderScope.containerOf(context)
        .read(appPreferencesProvider.notifier);
    expect(Theme.of(context).brightness, Brightness.dark);
    await controller.setTheme(ThemePreference.light);
    await tester.pumpAndSettle();
    expect(Theme.of(context).brightness, Brightness.light);
    expect(context.palette.background, const Color(0xFFF7F6F2));
    final homeSurface = tester.widget<ColoredBox>(find
        .descendant(
            of: find.byType(HomePage), matching: find.byType(ColoredBox))
        .first);
    expect(homeSurface.color, const Color(0xFFF7F6F2),
        reason: 'the real home page must consume the selected palette');
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await tester.pumpAndSettle();
    expect(Theme.of(context).brightness, Brightness.light);
    await controller.setTheme(ThemePreference.system);
    await tester.pumpAndSettle();
    expect(Theme.of(context).brightness, Brightness.dark);
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpAndSettle();
    expect(Theme.of(context).brightness, Brightness.light);
    // The fixed original photograph remains unchanged by appearance.
    expect(find.image(const AssetImage('assets/images/home_header.jpg')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hydrated light preference is used on the first routed frame',
      (tester) async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    appRouter.go('/home');
    await tester.pumpWidget(ProviderScope(overrides: [
      ...env.overrides,
      initialPreferencesProvider.overrideWithValue(const PreferencesState(
          preferences: AppPreferences(theme: ThemePreference.light))),
    ], child: const GRemoteApp()));
    final context = tester.element(find.byType(HomePage));
    expect(Theme.of(context).brightness, Brightness.light);
    await tester.pumpAndSettle();
  });
}
