import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/film/preview/film_comparison_controller.dart';
import 'package:gremote/imaging/imaging_engine.dart';
import 'film_preview_controller_test.dart' show ControlledEngine;

void main() {
  final catalog = FilmCatalog.fromJson(
      jsonDecode(File('assets/films/catalog.json').readAsStringSync()));
  final source = PreviewImage(width: 8, height: 8, rgba: Uint8List(256));
  test(
      'comparison serializes three results and keeps only latest pending batch',
      () async {
    final engine = ControlledEngine();
    final comparison = FilmComparisonController(engine);
    addTearDown(comparison.dispose);
    final recipes = [
      catalog.recipe(33),
      catalog.recipe(66),
      catalog.recipe(67)
    ];
    comparison.request(source, recipes);
    comparison.request(source, recipes.reversed.toList());
    comparison.request(source, recipes);
    expect(engine.calls, hasLength(1));
    expect(engine.calls.first.cancel!.isCancelled, isTrue);
    engine.finish(0, source);
    await Future<void>.delayed(Duration.zero);
    expect(engine.calls, hasLength(2));
    expect(comparison.images, isEmpty);
    for (var i = 1; i <= 3; i++) {
      engine.finish(i, source);
      await Future<void>.delayed(Duration.zero);
    }
    expect(engine.calls, hasLength(4));
    expect(comparison.images.length, 3);
    expect(comparison.busy, isFalse);
    expect(comparison.retainedBytes, lessThan(48 * 1024 * 1024));
  });
}
