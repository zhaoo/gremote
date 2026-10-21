import 'dart:convert';
import 'dart:typed_data';
import '../model/film_recipe.dart';

class RecipeCardCodec {
  static const schema = 'gremote.film-recipe/v1';
  static const maxBytes = 16384;

  static Uint8List encode(FilmRecipe recipe) {
    final bytes = Uint8List.fromList(utf8.encode(canonicalJson({
      'schema': schema,
      'recipe': recipe.toJson(),
      'fingerprint': recipe.fingerprint,
    })));
    if (bytes.length > maxBytes) throw const FormatException('配方卡过大');
    return bytes;
  }

  static FilmRecipe decode(Uint8List bytes) {
    if (bytes.length > maxBytes) throw const FormatException('配方卡过大');
    try {
      final card = jsonDecode(utf8.decode(bytes));
      if (card is! Map<String, dynamic> ||
          card.length != 3 ||
          card['schema'] != schema ||
          card['recipe'] is! Map<String, dynamic>) {
        throw const FormatException('不支持的配方卡');
      }
      final recipe =
          FilmRecipe.fromJson(card['recipe'] as Map<String, dynamic>);
      if (card['fingerprint'] != recipe.fingerprint) {
        throw const FormatException('配方卡校验失败');
      }
      return recipe;
    } on FormatException {
      rethrow;
    } on TypeError {
      throw const FormatException('配方卡格式错误');
    }
  }
}
