import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/camera/companion/camera_roll_index.dart';
import 'package:gremote/features/film_workbench/camera_roll_detail_page.dart';
import 'package:gremote/features/film_workbench/roll_archive_actions.dart';
import 'package:gremote/features/film_workbench/roll_detail_page.dart';
import 'package:gremote/features/film_workbench/rolls_page.dart';
import 'package:gremote/film/capture/active_roll_context.dart';
import 'package:gremote/film/capture/local_roll_importer.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/film/store/film_repository.dart';
import '../../support/camera_harness.dart';
import '../../support/test_darkroom.dart';

const _cameraRoll = CameraIndexedRoll(
    id: '11111111111111111111111111111111',
    target: 36,
    filmId: 66,
    journalCount: 2,
    status: CameraRollStatus.closed,
    isLatest: true);

class _Index extends CameraRollIndexController {
  @override
  CameraRollIndexState build() =>
      const CameraRollIndexState(latest: _cameraRoll, rolls: [_cameraRoll]);
  @override
  Future<void> refresh() async {}
}

void main() {
  testWidgets(
      'local roll deletion can be cancelled then removes grouping and active context only',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    final repo = FilmRepository(env.db);
    final catalog = FilmCatalog.fromJson(
        jsonDecode(File('assets/films/catalog.json').readAsStringSync())
            as Map<String, dynamic>);
    final recipe = catalog.recipe(33),
        roll = await repo.createRoll(
            name: '111', targetCount: 36, recipe: catalog.recipe(33));
    env.gateway.contentHashes[42] = 'a' * 64;
    await LocalRollImporter(repository: repo, gateway: env.gateway)
        .import(rollId: roll.id, mediaId: 42, recipe: recipe);
    final original = File('${env.dir.path}/original.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    await env.db.insert('album_collection',
        {'media_id': 42, 'source': 'camera', 'added_at': 1});
    final container = ProviderContainer(overrides: env.overrides);
    addTearDown(container.dispose);
    container.read(activeRollCaptureContextProvider.notifier).state =
        FrozenRollContext(
            rollId: roll.id, recipeJson: jsonEncode(recipe.toJson()));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: GRemoteTheme.dark, home: RollDetailPage(rollId: roll.id))));
    await tester.pumpAndSettle();
    expect(find.text('导出印样'), findsNothing);
    await tester.tap(find.byTooltip('胶卷更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除胶卷'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await repo.rolls(), hasLength(1));
    expect(await repo.listItems(roll.id), hasLength(1));
    await tester.tap(find.byTooltip('胶卷更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除胶卷'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(await repo.rolls(), isEmpty);
    expect(await repo.listItems(roll.id), isEmpty);
    expect(container.read(activeRollCaptureContextProvider), isNull);
    expect(await env.db.query('album_collection'), hasLength(1));
    expect(original.existsSync(), isTrue);
    expect(await repo.recipe(recipe.fingerprint), isNotNull);
  });
  testWidgets(
      'empty camera roll is compact and removing its record never mutates another camera',
      (tester) async {
    final harness = await CameraHarness.create(overrides: [
      cameraRollIndexProvider.overrideWith(_Index.new),
      cameraArchiveStableKeyProvider.overrideWithValue('camera-a')
    ]);
    addTearDown(harness.dispose);
    await tester.runAsync(harness.connect);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
            theme: GRemoteTheme.dark,
            home: const CameraRollDetailPage(_cameraRoll))));
    await tester.pumpAndSettle();
    expect(find.text('保存整卷'), findsNothing);
    expect(find.text('导出印样'), findsNothing);
    expect(find.text('计划张数'), findsNothing);
    expect(find.text('已找到原片'), findsNothing);
    expect(find.text('照片尚未读取'), findsOneWidget);
    await tester.tap(find.byTooltip('胶卷更多'));
    await tester.pumpAndSettle();
    final export = tester.widget<PopupMenuItem<String>>(find.ancestor(
        of: find.text('导出印样'), matching: find.byType(PopupMenuItem<String>)));
    expect(export.enabled, isFalse);
    await tester.tap(find.text('移除记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final repo = FilmRepository(harness.db);
    expect(await repo.hiddenCameraRolls('camera-a'), isEmpty);
    await tester.tap(find.byTooltip('胶卷更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    expect(await repo.hiddenCameraRolls('camera-a'), {_cameraRoll.id});
    expect(await repo.hiddenCameraRolls('camera-b'), isEmpty);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
            theme: GRemoteTheme.dark,
            home: const Scaffold(body: RollsPage()))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('latest-camera-roll')), findsNothing);
  });
}
