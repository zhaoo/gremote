import 'package:flutter/material.dart';

import 'router.dart';
import 'theme/app_theme.dart';

class GRemoteApp extends StatelessWidget {
  const GRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GRemote',
      debugShowCheckedModeBanner: false,
      theme: GRemoteTheme.dark,
      routerConfig: appRouter,
    );
  }
}
