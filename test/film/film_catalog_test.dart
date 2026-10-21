import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/film/model/film_recipe.dart';

void main() {
  late FilmCatalog catalog;
  setUpAll(() {
    catalog = FilmCatalog.fromJson(
        jsonDecode(File('assets/films/catalog.json').readAsStringSync())
            as Map<String, dynamic>);
  });
  test('stable catalog and capability-specific parameters', () {
    expect(catalog.entries.map((e) => e.id), containsAll([33, 67, 75, 289]));
    expect(catalog.film(67).parameters['filmExposure']!.maximum, 1);
    expect(catalog.film(75).parameters.containsKey('haloGain'), isFalse);
  });
  test('recipe identity excludes name and is unaffected by caller map mutation',
      () {
    final parameters = {'grain': 2};
    final a = catalog.recipe(33, name: '雨后', parameters: parameters);
    final before = a.fingerprint;
    parameters['grain'] = 3;
    expect(a.fingerprint, before);
    expect(
        a.fingerprint,
        catalog
            .recipe(33, name: '另一个名字', parameters: {'grain': 2}).fingerprint);
    expect(
        a.fingerprint,
        isNot(
            equals(catalog.recipe(33, parameters: {'grain': 3}).fingerprint)));
  });
  test(
      'unknown schema and impossible effect combinations cannot become recipes',
      () {
    final valid = catalog.recipe(75).toJson();
    expect(() => FilmRecipe.fromJson({...valid, 'schemaVersion': 3}),
        throwsFormatException);
    expect(() => catalog.recipe(67, parameters: {'filmExposure': 2}),
        throwsFormatException);
    expect(() => catalog.recipe(75, parameters: {'haloGain': 1}),
        throwsFormatException);
  });
}
