import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/companion_sync_controller.dart';
import 'package:gremote/camera/recipe/shooting_recipe.dart';
import 'package:gremote/features/camera/extensions_providers.dart';
import 'package:gremote/features/camera/shooting_recipes_page.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import 'package:gremote/film/store/sync_repository.dart';

import '../camera/companion_sync_controller_test.dart' show FakeCompanion;
import '../support/camera_harness.dart';

void main() {
  testWidgets('save, apply and undo restore the previous camera recipe',
      (tester) async {
    final harness = (await tester.runAsync(CameraHarness.create))!;
    addTearDown(harness.dispose);
    await tester.runAsync(harness.connect);
    final api = FakeCompanion();
    final sync = CompanionSyncController(
      api: api,
      repository: SyncRepository(harness.db),
      catalogHash: '05' * 32,
      rendererHash: '06' * 32,
      wait: () async {},
    );
    addTearDown(sync.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: harness.container,
      child: ProviderScope(
        overrides: [
          companionSyncControllerProvider.overrideWithValue(sync),
          cameraExtensionsControllerProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: ShootingRecipesPage()),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 18)));
      }
    }

    await settle();
    await tester.tap(find.text('保存当前配方'));
    await settle();
    await tester.enterText(find.byType(TextField), '街拍');
    await tester.tap(find.text('保存'));
    await settle();
    await settle();
    expect(find.text('街拍'), findsOneWidget);

    api.current =
        (jsonDecode(jsonEncode(api.current)) as Map).cast<String, Object?>();
    (((api.current['slots'] as List)[0] as Map)['parameters'] as Map)['grain'] =
        3;
    api.sequence++;
    await tester.tap(find.text('街拍'));
    await settle();
    await tester.tap(find.text('应用'));
    await settle();
    await settle();
    expect(
        sync.state.snapshot!.slots[0]['parameters'], containsPair('grain', 0));
    await tester.tap(find.text('撤销上次应用'));
    await settle();
    await settle();
    expect(
        sync.state.snapshot!.slots[0]['parameters'], containsPair('grain', 3));

    final recorded = ShootingRecipe(
      name: '手机记录的拍摄配方',
      catalog: sync.catalogHash,
      renderer: sync.rendererHash,
      film: {
        ...sync.state.snapshot!.slots[0],
        'parameters': {
          ...(sync.state.snapshot!.slots[0]['parameters'] as Map),
          'grain': 1,
        },
      },
      settings: const {},
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: harness.container,
      child: ProviderScope(
        overrides: [
          companionSyncControllerProvider.overrideWithValue(sync),
          cameraExtensionsControllerProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
            home: ShootingRecipesPage(
          key: const ValueKey('recorded'),
          recordedRecipe: recorded,
          applyOnOpen: true,
        )),
      ),
    ));
    await settle();
    await settle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        sync.state.snapshot!.slots[0]['parameters'], containsPair('grain', 1));
    expect(find.text('撤销上次应用'), findsOneWidget);
  });
}
