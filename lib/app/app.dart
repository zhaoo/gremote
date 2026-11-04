import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../settings/preferences_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/film_workbench/workbench_providers.dart';
import '../features/film_workbench/companion_providers.dart';

import '../camera/connection/connection_controller.dart';
import 'app_presence.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class GRemoteApp extends ConsumerStatefulWidget {
  const GRemoteApp({super.key});

  @override
  ConsumerState<GRemoteApp> createState() => _GRemoteAppState();
}

class _GRemoteAppState extends ConsumerState<GRemoteApp> {
  late final AppLifecycleListener _lifecycle;
  Timer? _wifiAdoption;
  bool get _supportsWifiAdoption => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      ref.read(appForegroundProvider.notifier).state =
          state == AppLifecycleState.resumed ||
              state == AppLifecycleState.inactive;
      if (state == AppLifecycleState.resumed) _adoptWifi();
    });
    if (_supportsWifiAdoption && !useFakeCamera) {
      _wifiAdoption =
          Timer.periodic(const Duration(seconds: 5), (_) => _adoptWifi());
      WidgetsBinding.instance.addPostFrameCallback((_) => _adoptWifi());
    }
  }

  void _adoptWifi() {
    if (!mounted ||
        !_supportsWifiAdoption ||
        useFakeCamera ||
        !ref.read(appForegroundProvider)) return;
    unawaited(
        ref.read(connectionControllerProvider.notifier).adoptConnectedWifi());
  }

  @override
  void dispose() {
    _wifiAdoption?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(activeRollHydrationProvider);
    ref.watch(effectiveCompanionIdentityProvider);
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
