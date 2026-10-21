import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/film/export/recipe_card_codec.dart';

void main() {
  final catalog = FilmCatalog.fromJson(
      jsonDecode(File('assets/films/catalog.json').readAsStringSync())
          as Map<String, dynamic>);
  test('recipe card round trips rendering identity without private metadata',
      () {
    final recipe = catalog
        .recipe(67, name: '街角', parameters: {'grain': 2, 'filmExposure': 1});
    final bytes = RecipeCardCodec.encode(recipe),
        card = jsonDecode(utf8.decode(bytes)) as Map;
    expect(RecipeCardCodec.decode(bytes).fingerprint, recipe.fingerprint);
    expect(card.keys.toSet(), {'schema', 'recipe', 'fingerprint'});
    expect(utf8.decode(bytes), isNot(contains('latitude')));
  });
  test('unknown schema bad fingerprint and oversized card reject before import',
      () {
    final valid =
        jsonDecode(utf8.decode(RecipeCardCodec.encode(catalog.recipe(33))))
            as Map<String, dynamic>;
    for (final change in [
      {'schema': 'unknown'},
      {'fingerprint': '0' * 64},
      {'location': 'private'}
    ]) {
      expect(
          () => RecipeCardCodec.decode(Uint8List.fromList(
              utf8.encode(jsonEncode({...valid, ...change})))),
          throwsFormatException);
    }
    expect(
        () => RecipeCardCodec.decode(Uint8List(16385)), throwsFormatException);
  });
}
