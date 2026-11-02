import 'dart:async';
import 'package:gremote/darkroom/model/export_recipe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/darkroom/model/photo_edits.dart';
import 'package:gremote/features/darkroom/editor/editor_controller.dart';
import 'package:gremote/imaging/imaging_exception.dart';
import '../support/fake_media_gateway.dart';
import '../support/test_darkroom.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestDarkroom env;
  late ProviderContainer c;
  late EditorController editor;
  setUp(() async {
    env = await TestDarkroom.create(
        gateway:
            FakeMediaGateway(entries: [mediaEntry(3)], exif: {3: grMeta()}));
    c = ProviderContainer(overrides: env.overrides);
    await c.read(localMediaRepositoryProvider).scan().drain<void>();
    c.listen(editorProvider(3), (_, __) {});
    editor = c.read(editorProvider(3).notifier);
    for (var i = 0; i < 30 && c.read(editorProvider(3)).base == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await editor.flushPreview();
  });
  tearDown(() async {
    c.dispose();
    await env.close();
  });

  test('tool cancel restores document and discards draft history', () async {
    final before = c.read(editorProvider(3)).recipe;
    editor.beginTool();
    editor.setEdits(before.edits.withValue(PhotoAdjustment.exposure, 1));
    await editor.flushPreview();
    expect(
        c.read(editorProvider(3)).recipe.edits.value(PhotoAdjustment.exposure),
        1);
    expect(await env.store.loadEdit(3), isNull);
    editor.cancelTool();
    await editor.flushPreview();
    expect(c.read(editorProvider(3)).recipe, before);
    expect(c.read(editorProvider(3)).canUndo, isFalse);
  });

  test('one drag undoes as one operation and committed edits reopen intact',
      () async {
    editor.beginTool();
    editor.beginGesture();
    for (var i = 1; i <= 20; i++) {
      editor.setEdits(c
          .read(editorProvider(3))
          .recipe
          .edits
          .withValue(PhotoAdjustment.grain, i / 100));
    }
    editor.endGesture();
    expect(c.read(editorProvider(3)).canUndo, isTrue);
    editor.undo();
    expect(
        c.read(editorProvider(3)).recipe.edits.value(PhotoAdjustment.grain), 0);
    expect(c.read(editorProvider(3)).canUndo, isFalse);
    editor.redo();
    expect(c.read(editorProvider(3)).recipe.edits.value(PhotoAdjustment.grain),
        .2);
    editor.commitTool();
    await editor.flushEdits();
    final doc = (await env.store.loadEdit(3))!;
    expect(doc.recipe.edits.value(PhotoAdjustment.grain), .2);
    expect(doc.recipe.edits.seed, 7331);
  });

  test('crop preview exposes full image until apply then uses cropped size',
      () async {
    editor.beginTool(crop: true);
    editor.setEdits(c.read(editorProvider(3)).recipe.edits.copyWith(
        crop: const CropEdit(quarterTurns: 1, width: .5, height: .5)));
    await editor.flushPreview();
    expect(c.read(editorProvider(3)).graded!.width, 4);
    expect(c.read(editorProvider(3)).graded!.height, 6);
    editor.commitTool();
    await editor.flushPreview();
    expect(c.read(editorProvider(3)).graded!.width, 2);
    expect(c.read(editorProvider(3)).graded!.height, 3);
    final r = env.engine.renderCalls.last;
    expect(r.adjustments[32], .5);
    await editor.export();
    expect(env.engine.jobs.last.photoWidth, 2000);
    expect(env.engine.jobs.last.photoHeight, 3000);
    expect(env.engine.jobs.last.adjustments![32], .5);
  });

  test('rapid updates serialize native work and only latest preview wins',
      () async {
    final gate = Completer<void>();
    env.engine.renderGate = gate.future;
    editor.setEdits(const PhotoEdits().withValue(PhotoAdjustment.exposure, .1));
    await Future<void>.delayed(Duration.zero);
    for (var i = 2; i < 15; i++) {
      editor.setEdits(
          const PhotoEdits().withValue(PhotoAdjustment.exposure, i / 10));
    }
    expect(env.engine.activeRenders, 1);
    gate.complete();
    await editor.flushPreview();
    expect(env.engine.maxActiveRenders, 1);
    expect(env.engine.renderCalls.last.adjustments[1], closeTo(1.4, .00001));
    expect(env.engine.renderCalls.length, 2);
    expect(c.read(editorProvider(3)).rendering, isFalse);
  });

  test('active tool publishes completed draft while newest render is pending',
      () async {
    final first = Completer<void>(), newest = Completer<void>();
    editor.beginTool();
    editor.beginGesture();
    env.engine.renderGate = first.future;
    editor.setEdits(const PhotoEdits().withValue(PhotoAdjustment.exposure, .2));
    await Future<void>.delayed(Duration.zero);
    env.engine.renderGate = newest.future;
    editor
        .setEdits(const PhotoEdits().withValue(PhotoAdjustment.exposure, 1.4));
    first.complete();
    await Future<void>.delayed(Duration.zero);
    final during = c.read(editorProvider(3));
    expect(during.rendering, isTrue);
    expect(during.renderedEdits!.value(PhotoAdjustment.exposure), .2);
    expect(during.recipe.edits.value(PhotoAdjustment.exposure), 1.4);
    newest.complete();
    await editor.flushPreview();
    expect(
        c
            .read(editorProvider(3))
            .renderedEdits!
            .value(PhotoAdjustment.exposure),
        1.4);
    expect(env.engine.maxActiveRenders, 1);
  });

  test('intermediate crop frame keeps its own geometry until newest is ready',
      () async {
    final first = Completer<void>(), newest = Completer<void>();
    editor.beginTool(crop: true);
    await editor.flushPreview();
    editor.beginGesture();
    env.engine.renderGate = first.future;
    editor.setEdits(
        const PhotoEdits().copyWith(crop: const CropEdit(quarterTurns: 1)));
    await Future<void>.delayed(Duration.zero);
    env.engine.renderGate = newest.future;
    editor.setEdits(
        const PhotoEdits().copyWith(crop: const CropEdit(quarterTurns: 2)));
    first.complete();
    await Future<void>.delayed(Duration.zero);
    final during = c.read(editorProvider(3));
    expect(during.graded!.width, 4);
    expect(during.graded!.height, 6);
    expect(during.layout!.canvasWidth / during.layout!.canvasHeight,
        closeTo(2 / 3, .00001));
    expect(during.recipe.edits.crop.quarterTurns, 2);
    newest.complete();
    await editor.flushPreview();
    final finished = c.read(editorProvider(3));
    expect(finished.graded!.width, 6);
    expect(finished.graded!.height, 4);
    expect(finished.layout!.canvasWidth / finished.layout!.canvasHeight, 1.5);
  });

  test('applying crop rejects unfinished full-image crop-mode preview',
      () async {
    editor.beginTool(crop: true);
    await editor.flushPreview();
    final displayed = c.read(editorProvider(3)).graded;
    final first = Completer<void>(), newest = Completer<void>();
    editor.beginGesture();
    env.engine.renderGate = first.future;
    editor.setEdits(const PhotoEdits()
        .copyWith(crop: const CropEdit(quarterTurns: 1, width: .5)));
    await Future<void>.delayed(Duration.zero);
    env.engine.renderGate = newest.future;
    editor.commitTool();
    first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(editorProvider(3)).graded, same(displayed));
    newest.complete();
    await editor.flushPreview();
    final finished = c.read(editorProvider(3));
    expect(finished.cropEditing, isFalse);
    expect(finished.graded!.width, 2);
    expect(finished.graded!.height, 6);
    expect(finished.layout!.canvasWidth / finished.layout!.canvasHeight,
        closeTo(1 / 3, .00001));
  });

  for (final barrier in [
    'cancel',
    'undo',
    'tool switch',
    'LUT',
    'same LUT',
    'reset',
    'preset'
  ]) {
    test('$barrier prevents a superseded tool render from flashing', () async {
      editor
          .setEdits(const PhotoEdits().withValue(PhotoAdjustment.exposure, .2));
      await editor.flushPreview();
      final displayed = c.read(editorProvider(3)).graded;
      final first = Completer<void>(), newest = Completer<void>();
      editor.beginTool();
      editor.beginGesture();
      env.engine.renderGate = first.future;
      editor
          .setEdits(const PhotoEdits().withValue(PhotoAdjustment.exposure, .8));
      await Future<void>.delayed(Duration.zero);
      env.engine.renderGate = newest.future;
      switch (barrier) {
        case 'cancel':
          editor.cancelTool();
        case 'undo':
          editor.endGesture();
          editor.undo();
        case 'tool switch':
          editor.beginTool();
          editor.setEdits(
              const PhotoEdits().withValue(PhotoAdjustment.exposure, 1.2));
        case 'LUT':
          unawaited(editor.setLut(c.read(editorProvider(3)).luts.first.id));
        case 'same LUT':
          unawaited(editor.setLut(null));
        case 'reset':
          editor.resetAll();
        case 'preset':
          editor.applyPreset(const ExportRecipe().copyWith(
              edits:
                  const PhotoEdits().withValue(PhotoAdjustment.exposure, 1.2)));
      }
      final published = <double>[];
      final subscription = c.listen(editorProvider(3), (_, next) {
        published.add(next.renderedEdits!.value(PhotoAdjustment.exposure));
      });
      first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(published, isNot(contains(.8)));
      if (barrier != 'reset') {
        expect(c.read(editorProvider(3)).graded, same(displayed));
      }
      newest.complete();
      await editor.flushPreview();
      subscription.close();
      final finished = c.read(editorProvider(3));
      expect(finished.rendering, isFalse);
      expect(finished.renderedEdits, finished.recipe.edits);
    });
  }

  test('redo blocks an unfinished undo frame from replacing the preview',
      () async {
    editor.setEdits(const PhotoEdits().withValue(PhotoAdjustment.exposure, .2));
    await editor.flushPreview();
    editor.beginTool();
    editor.setEdits(const PhotoEdits().withValue(PhotoAdjustment.exposure, .8));
    await editor.flushPreview();
    final displayed = c.read(editorProvider(3)).graded;
    final first = Completer<void>(), newest = Completer<void>();
    env.engine.renderGate = first.future;
    editor.undo();
    await Future<void>.delayed(Duration.zero);
    env.engine.renderGate = newest.future;
    editor.redo();
    final published = <double>[];
    final subscription = c.listen(editorProvider(3), (_, next) {
      published.add(next.renderedEdits!.value(PhotoAdjustment.exposure));
    });
    first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(published, isNot(contains(.2)));
    expect(c.read(editorProvider(3)).graded, same(displayed));
    newest.complete();
    await editor.flushPreview();
    subscription.close();
    expect(
        c
            .read(editorProvider(3))
            .renderedEdits!
            .value(PhotoAdjustment.exposure),
        .8);
  });

  test('tool switch discards old failure and resumes the queued preview',
      () async {
    editor.beginTool();
    final first = Completer<void>(), newest = Completer<void>();
    env.engine.renderGate = first.future;
    env.engine.renderFailures[1] = ImagingErrorCode.invalidArgument;
    editor.setEdits(const PhotoEdits().withValue(PhotoAdjustment.exposure, .8));
    await Future<void>.delayed(Duration.zero);
    env.engine.renderGate = newest.future;
    editor.beginTool();
    first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(editorProvider(3)).error, isNull);
    expect(c.read(editorProvider(3)).rendering, isTrue);
    newest.complete();
    await editor.flushPreview();
    expect(c.read(editorProvider(3)).error, isNull);
    expect(
        c
            .read(editorProvider(3))
            .renderedEdits!
            .value(PhotoAdjustment.exposure),
        .8);
    expect(c.read(editorProvider(3)).rendering, isFalse);
  });

  test('a failed current render does not block later adjustments', () async {
    env.engine.renderFailures[1] = ImagingErrorCode.invalidArgument;
    editor.setEdits(const PhotoEdits().withValue(PhotoAdjustment.exposure, .2));
    await editor.flushPreview();
    expect(c.read(editorProvider(3)).error, contains('预览处理失败'));
    expect(c.read(editorProvider(3)).rendering, isFalse);
    editor.setEdits(const PhotoEdits().withValue(PhotoAdjustment.exposure, .4));
    await editor.flushPreview();
    expect(c.read(editorProvider(3)).error, isNull);
    expect(
        c
            .read(editorProvider(3))
            .renderedEdits!
            .value(PhotoAdjustment.exposure),
        .4);
  });

  test('autosave failure survives preview and retry persists latest edits',
      () async {
    await env.db.execute(
        "CREATE TRIGGER reject_edit BEFORE INSERT ON edit_documents BEGIN SELECT RAISE(FAIL, 'disk full'); END");
    editor.setEdits(const PhotoEdits().withValue(PhotoAdjustment.grain, .4));
    await editor.flushEdits();
    await editor.flushPreview();
    expect(c.read(editorProvider(3)).saveError, contains('保存失败'));
    await env.db.execute('DROP TRIGGER reject_edit');
    await editor.retrySave();
    expect(c.read(editorProvider(3)).saveError, isNull);
    expect(
        (await env.store.loadEdit(3))!
            .recipe
            .edits
            .value(PhotoAdjustment.grain),
        .4);
  });

  test('unavailable LUT reports error and choosing original recovers',
      () async {
    await editor.setLut('deleted-lut');
    expect(c.read(editorProvider(3)).error, contains('预览处理失败'));
    await editor.setLut(null);
    expect(c.read(editorProvider(3)).error, isNull);
    expect(
        c.read(editorProvider(3)).graded, same(c.read(editorProvider(3)).base));
  });
  test('frame width and date stamp are individual undoable persisted changes',
      () async {
    editor.setFrameWidth(.08);
    await editor.flushEdits();
    expect(c.read(editorProvider(3)).recipe.frameWidth, .08);
    expect((await env.store.loadEdit(3))!.recipe.frameWidth, .08);
    editor.setDateStamp(true);
    await editor.flushEdits();
    expect(c.read(editorProvider(3)).recipe.dateStamp, isTrue);
    expect((await env.store.loadEdit(3))!.recipe.dateStamp, isTrue);
    editor.undo();
    expect(c.read(editorProvider(3)).recipe.dateStamp, isFalse);
    expect(c.read(editorProvider(3)).recipe.frameWidth, .08);
    editor.redo();
    expect(c.read(editorProvider(3)).recipe.dateStamp, isTrue);
  });

  test('save retry inside a tool never persists unconfirmed draft', () async {
    editor.setEdits(const PhotoEdits().withValue(PhotoAdjustment.grain, .2));
    await editor.flushEdits();
    editor.beginTool();
    editor.setEdits(c
        .read(editorProvider(3))
        .recipe
        .edits
        .withValue(PhotoAdjustment.grain, .8));
    await editor.retrySave();
    editor.cancelTool();
    await editor.flushPreview();
    expect(c.read(editorProvider(3)).recipe.edits.value(PhotoAdjustment.grain),
        .2);
    expect(
        (await env.store.loadEdit(3))!
            .recipe
            .edits
            .value(PhotoAdjustment.grain),
        .2);
  });

  test('late LUT import refreshes library but never overrides cancelled tool',
      () async {
    final gate = Completer<void>();
    env.engine.validationGate = gate.future;
    final bytes = await c
        .read(lutLibraryProvider)
        .load(c.read(editorProvider(3)).luts.first.id);
    editor.beginTool();
    final importing = editor.importLut('cancelled.cube', bytes);
    await Future<void>.delayed(Duration.zero);
    editor.cancelTool();
    gate.complete();
    await importing;
    await editor.flushEdits();
    expect(c.read(editorProvider(3)).recipe.lutId, isNull);
    expect(await env.store.importedLuts(), hasLength(1));
    expect(await env.store.loadEdit(3), isNull);
  });

  test('late LUT import never overrides newer explicit LUT selection',
      () async {
    final gate = Completer<void>();
    env.engine.validationGate = gate.future;
    final first = c.read(editorProvider(3)).luts.first.id;
    final bytes = await c.read(lutLibraryProvider).load(first);
    editor.beginTool();
    final importing = editor.importLut('late.cube', bytes);
    await Future<void>.delayed(Duration.zero);
    await editor.setLut(first);
    gate.complete();
    await importing;
    expect(c.read(editorProvider(3)).recipe.lutId, first);
  });

  test(
      'locked crop preset adapts to destination orientation and survives resize',
      () async {
    editor.applyPreset(const ExportRecipe(edits: PhotoEdits()).copyWith(
        edits: const PhotoEdits().copyWith(
            crop: const CropEdit(
                width: 1, height: 2 / 3, top: 1 / 6, aspectRatio: 1))));
    final crop = c.read(editorProvider(3)).recipe.edits.crop;
    expect(crop.outputSize(6000, 4000), (4000, 4000));
    expect(crop.left, closeTo(1 / 6, .00001));
    expect(crop.top, 0);
    expect(crop.aspectRatio, 1);
    await editor.flushEdits();
    expect(
        (await env.store.loadEdit(3))!.recipe.edits.crop.outputSize(6000, 4000),
        (4000, 4000));
  });
}
