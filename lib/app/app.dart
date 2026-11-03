import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../settings/preferences_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/film_workbench/workbench_providers.dart';

import 'router.dart';
import 'theme/app_theme.dart';

class GRemoteApp extends ConsumerWidget {
  const GRemoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(activeRollHydrationProvider);
    return MaterialApp.router(
      title: 'GRemote',
      debugShowCheckedModeBanner: false,
      theme: GRemoteTheme.light,
      darkTheme: GRemoteTheme.dark,
      themeMode: ref
          .watch(appPreferencesProvider.select((s) => s.preferences.theme))
          .themeMode,
      themeAnimationDuration: WidgetsBinding.instance.platformDispatcher
              .accessibilityFeatures.disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 180),
      builder: (context, child) {
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: theme.scaffoldBackgroundColor,
            systemNavigationBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: appRouter,
    );
  }
}
