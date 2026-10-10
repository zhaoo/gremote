import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/capture/capture_tracker.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/camera/recipe/recipe_store.dart';
import 'package:gremote/darkroom/model/export_recipe.dart';
import 'package:gremote/features/library/library_controller.dart';

import '../support/fake_media_gateway.dart';
import '../support/test_darkroom.dart';

CaptureRecord _capture(String base, String recipeId) => CaptureRecord(
      dir: '100RICOH',
      baseName: base,
      files: ['$base.JPG'],
      wallSeconds: wallSecondsOf('2026-10-10 08:30:00')!,
      timeSource: TimeSource.camera,
      source: CaptureSource.app,
      recipeId: recipeId,
    );

void main() {
  test('library filters tagged photos and builds per-recipe export jobs',
      () async {
    final gateway = FakeMediaGateway(
      entries: [mediaEntry(1), mediaEntry(2), mediaEntry(3)],
      exif: {1: grMeta(), 2: grMeta(), 3: grMeta()},
    );
    final env = await TestDarkroom.create(gateway: gateway);
    addTearDown(env.close);
    final container = ProviderContainer(overrides: env.overrides);
    addTearDown(container.dispose);
    final recipeStore = container.read(recipeStoreProvider);
    final preset =
        await env.store.savePreset('正片出图', const ExportRecipe(quality: 90));
    final usable = await recipeStore.create(
        name: '正片', effect: 'positiveFilm', exportPresetId: preset.id);
    final noExport = await recipeStore.create(name: '只切机内', effect: 'vivid');
    await recipeStore.addTag(_capture('R001', usable.id), usable.id);
    await recipeStore.addTag(_capture('R002', noExport.id), noExport.id);

    final controller = container.read(libraryControllerProvider.notifier);
    await controller.refresh();
    expect(container.read(libraryControllerProvider).tags.keys,
        containsAll([1, 2]));

    await controller.setRecipeOnly(true);
    expect(container.read(libraryControllerProvider).items.map((i) => i.id),
        [2, 1]);
    controller.toggle(1);
    controller.toggle(2);
    final jobs = await controller.recipeJobs();
    expect(jobs.jobs, hasLength(1));
    expect(jobs.jobs.single.$1.id, 1);
    expect(jobs.jobs.single.$2.quality, 90);
    expect(jobs.skipped, 1);
  });
}
