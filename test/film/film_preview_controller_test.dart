import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/film/model/film_recipe.dart';
import 'package:gremote/film/preview/film_preview_engine.dart';
import 'package:gremote/film/preview/film_preview_controller.dart';
import 'package:gremote/imaging/imaging_engine.dart';

class ControlledEngine implements FilmPreviewEngine {
  final calls = <({
    FilmRecipe recipe,
    int generation,
    PreviewStage stage,
    Completer<FilmPreviewResult> result,
    ImagingCancelToken? cancel
  })>[];
  @override
  Future<FilmPreviewResult> render(
      {required PreviewImage source,
      required FilmRecipe recipe,
      required PreviewStage stage,
      required int generation,
      ImagingCancelToken? cancel,
      int maxEdge = 960}) {
    final result = Completer<FilmPreviewResult>();
    calls.add((
      recipe: recipe,
      generation: generation,
      stage: stage,
      result: result,
      cancel: cancel
    ));
    return result.future;
  }

  void finish(int i, PreviewImage image) {
    final c = calls[i];
    c.result.complete(FilmPreviewResult(
        image: image,
        recipeFingerprint: c.recipe.fingerprint,
        generation: c.generation,
        stage: c.stage));
  }
}

void main() {
  final catalog = FilmCatalog.fromJson(
      jsonDecode(File('assets/films/catalog.json').readAsStringSync())
          as Map<String, dynamic>);
  PreviewImage image() =>
      PreviewImage(width: 8, height: 8, rgba: Uint8List(256));
  test('only latest pending frame is rendered and stale completion never wins',
      () async {
    final engine = ControlledEngine(),
        controller = FilmPreviewController(engine);
    addTearDown(controller.dispose);
    controller.request(source: image(), recipe: catalog.recipe(33));
    controller.request(source: image(), recipe: catalog.recipe(66));
    controller.request(
        source: image(), recipe: catalog.recipe(75, parameters: {'grain': 2}));
    expect(engine.calls.length, 1);
    expect(engine.calls.first.cancel!.isCancelled, isTrue);
    engine.finish(0, image());
    await Future<void>.delayed(Duration.zero);
    expect(controller.result, isNull);
    expect(engine.calls.length, 2);
    engine.finish(1, image());
    await Future<void>.delayed(Duration.zero);
    expect(controller.result!.recipeFingerprint,
        catalog.recipe(75, parameters: {'grain': 2}).fingerprint);
    engine.finish(2, image());
    await Future<void>.delayed(Duration.zero);
    expect(controller.result!.generation, 3);
    expect(controller.busy, isFalse);
    expect(controller.retainedBytes, lessThanOrEqualTo(48 * 1024 * 1024));
  });
  test(
      'disposing does not release native cancellation memory before worker exits',
      () async {
    final engine = ControlledEngine(),
        controller = FilmPreviewController(engine);
    controller.request(source: image(), recipe: catalog.recipe(33));
    controller.dispose();
    expect(engine.calls.single.cancel!.isCancelled, isTrue);
    engine.finish(0, image());
    await Future<void>.delayed(Duration.zero);
    expect(engine.calls, hasLength(1));
  });
  test('already processed image is not automatically colored twice', () {
    final engine = ControlledEngine(),
        controller = FilmPreviewController(engine);
    addTearDown(controller.dispose);
    final source = image();
    controller.request(
        source: source, recipe: catalog.recipe(33), alreadyProcessed: true);
    expect(engine.calls, isEmpty);
    expect(controller.result!.image, same(source));
    expect(controller.result!.bypassed, isTrue);
  });
  test('FFI preview renders real film pixels across the pinned catalog',
      () async {
    const engine = FfiFilmPreviewEngine(
        libraryPath: 'native/imaging/build/host/libgremote_imaging.dylib');
    final source = image();
    source.rgba.fillRange(0, source.rgba.length, 90);
    for (final film in catalog.entries) {
      final rendered = await engine.render(
          source: source,
          recipe: catalog.recipe(film.id),
          stage: PreviewStage.full,
          generation: 1);
      expect(rendered.image.rgba.length, 256, reason: film.name);
    }
  });
}
