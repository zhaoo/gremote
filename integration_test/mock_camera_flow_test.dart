import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gremote/app/app.dart';
import 'package:gremote/app/router.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/storage/gremote_database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fake camera connects, previews, shoots, and stays ready',
      (tester) async {
    final db = await GRemoteDatabase.open();
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const GRemoteApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('连接 GR III'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('RICOH GR III'), findsOneWidget);

    await tester.tap(find.text('进入实景遥控'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Image), findsOneWidget);

    final shutter = find.byKey(const Key('shutter-button'));
    final gesture = await tester.startGesture(tester.getCenter(shutter));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    appRouter.go('/home');
    await tester.pumpAndSettle();
    expect(find.text('已连接'), findsOneWidget);
  });
}
