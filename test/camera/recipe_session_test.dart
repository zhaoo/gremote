import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/capture/capture_tracker.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/params/param_writer.dart';
import 'package:gremote/camera/recipe/recipe_session.dart';
import 'package:gremote/camera/recipe/recipe_store.dart';

import '../support/camera_harness.dart';

void main() {
  test('activation writes the camera effect and body changes detach it',
      () async {
    final h = await CameraHarness.create();
    addTearDown(h.dispose);
    await h.connect();
    final store = h.container.read(recipeStoreProvider);
    final recipe = await store.create(name: '正片', effect: 'positiveFilm');
    final session = h.container.read(recipeSessionProvider.notifier);

    expect(await session.activate(recipe), isA<WriteConfirmed>());
    expect(h.container.read(recipeSessionProvider).active.id, recipe.id);
    expect(h.container.read(recipeSessionProvider).detached, isFalse);

    h.camera.bodyChange('effect', 'standard');
    await pumpEventQueue();
    expect(h.container.read(recipeSessionProvider).detached, isTrue);
  });

  test('a program recipe ID overrides the active session recipe', () async {
    final h = await CameraHarness.create();
    addTearDown(h.dispose);
    await h.connect();
    final store = h.container.read(recipeStoreProvider);
    final active = await store.create(name: '活跃', effect: 'vivid');
    final bracket = await store.create(name: '包围', effect: 'positiveFilm');
    final session = h.container.read(recipeSessionProvider.notifier);
    await session.activate(active);

    await h.controller.shootAndAwait(
      autoFocus: false,
      context: CaptureContext(
        source: CaptureSource.program,
        recipeId: bracket.id,
        effect: bracket.effect,
      ),
    );
    await pumpEventQueue();

    final tags = await store.tagsForBaseNames(['R0000001']);
    expect(tags.single.recipeId, bracket.id);
  });

  test('factory and detached sessions do not auto-tag', () async {
    final h = await CameraHarness.create();
    addTearDown(h.dispose);
    await h.connect();
    final store = h.container.read(recipeStoreProvider);
    h.container.read(recipeSessionProvider);

    await h.controller.shootAndAwait(
      autoFocus: false,
      context: const CaptureContext(source: CaptureSource.app),
    );
    await pumpEventQueue();
    expect(await store.tagsForBaseNames(['R0000001']), isEmpty);
  });

  test('disconnect resets the session to factory', () async {
    final h = await CameraHarness.create();
    addTearDown(h.dispose);
    await h.connect();
    final recipe = await h.container
        .read(recipeStoreProvider)
        .create(name: '正片', effect: 'positiveFilm');
    await h.container.read(recipeSessionProvider.notifier).activate(recipe);

    await h.container.read(connectionControllerProvider.notifier).cancel();
    await pumpEventQueue();

    expect(h.container.read(recipeSessionProvider).active.isFactory, isTrue);
  });
}
