import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../features/darkroom/darkroom_page.dart';
import '../features/darkroom/editor/editor_page.dart';
import '../features/home/home_page.dart';
import '../features/library/batch_export_page.dart';
import '../features/library/library_page.dart';
import '../features/settings/protocol_probe_page.dart';
import '../features/shoot/shoot_page.dart';
import 'theme/app_colors.dart';

final _homeKey = GlobalKey<NavigatorState>();
final _shootKey = GlobalKey<NavigatorState>();
final _libraryKey = GlobalKey<NavigatorState>();
final _darkroomKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          GRemoteShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          navigatorKey: _homeKey,
          routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomePage()),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shootKey,
          routes: [
            GoRoute(path: '/shoot', builder: (_, __) => const ShootPage()),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _libraryKey,
          routes: [
            GoRoute(path: '/library', builder: (_, __) => const LibraryPage()),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _darkroomKey,
          routes: [
            GoRoute(
                path: '/darkroom', builder: (_, __) => const DarkroomPage()),
          ],
        ),
      ],
    ),
    GoRoute(path: '/export-queue', builder: (_, __) => const BatchExportPage()),
    GoRoute(path: '/probe', builder: (_, __) => const ProtocolProbePage()),
    GoRoute(
      path: '/edit/:mediaId',
      builder: (_, state) => EditorPage(
          mediaId: int.tryParse(state.pathParameters['mediaId'] ?? '') ?? -1),
    ),
  ],
);

class GRemoteShell extends StatelessWidget {
  const GRemoteShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final motionDuration =
        MediaQuery.maybeOf(context)?.disableAnimations == true
            ? Duration.zero
            : const Duration(milliseconds: 180);
    final hideNavigation = navigationShell.currentIndex == 1;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: hideNavigation
          ? null
          : SafeArea(
              top: false,
              child: Container(
                height: 76,
                decoration: const BoxDecoration(
                  color: GRemoteColors.night,
                  border: Border(top: BorderSide(color: GRemoteColors.divider)),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          _destination(0, '首页', Icons.home_outlined, Icons.home,
                              motionDuration),
                          _destination(1, '拍摄', Icons.camera_alt_outlined,
                              Icons.camera_alt, motionDuration),
                          _destination(2, '图库', Icons.photo_outlined,
                              Icons.photo, motionDuration),
                          _destination(3, '暗房', Icons.tune_outlined, Icons.tune,
                              motionDuration),
                        ],
                      ),
                    ),
                    const Text('GOOD PHOTOS  A KINDER WORLD',
                        style: TextStyle(
                            color: GRemoteColors.muted,
                            fontSize: 7,
                            letterSpacing: 2)),
                    const SizedBox(height: 3),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _destination(int index, String label, IconData icon,
      IconData activeIcon, Duration motionDuration) {
    final selected = navigationShell.currentIndex == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: () {
            if (index != 1) {
              unawaited(SystemChrome.setPreferredOrientations(
                const [DeviceOrientation.portraitUp],
              ));
            }
            navigationShell.goBranch(index,
                initialLocation: index == navigationShell.currentIndex);
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1,
                duration: motionDuration,
                child: Icon(selected ? activeIcon : icon,
                    size: 23,
                    color: selected ? GRemoteColors.gold : GRemoteColors.muted),
              ),
              const SizedBox(height: 5),
              Text(label,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? GRemoteColors.gold : GRemoteColors.muted,
                  )),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: motionDuration,
                width: selected ? 20 : 0,
                height: 2,
                color: GRemoteColors.gold,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
