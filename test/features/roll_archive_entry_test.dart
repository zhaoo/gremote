import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/features/film_workbench/rolls_page.dart';
import 'package:gremote/features/film_workbench/workbench_providers.dart';

void main() {
  testWidgets(
      'archive import opens camera gallery without creating a local roll',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const RollsPage()),
      GoRoute(
          path: '/library',
          builder: (_, state) => Scaffold(
              body: Text('来源：${state.uri.queryParameters['source']}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [filmRollsProvider.overrideWith((ref) async => [])],
        child: MaterialApp.router(
            theme: GRemoteTheme.dark, routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.textContaining('无需新建胶卷'), findsOneWidget);
    await tester.tap(find.text('从相机导入胶卷'));
    await tester.pumpAndSettle();
    expect(find.text('来源：camera'), findsOneWidget);
  });
}
