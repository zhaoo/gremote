import 'package:flutter/material.dart';
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
      theme: GRemoteTheme.dark,
      routerConfig: appRouter,
    );
  }
}
