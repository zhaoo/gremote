import '../model/film_recipe.dart';

class FilmParameter {
  const FilmParameter(
      {required this.minimum,
      required this.maximum,
      required this.defaultValue,
      required this.label});
  final int minimum, maximum, defaultValue;
  final String label;
  factory FilmParameter.fromJson(Map<String, dynamic> v) => FilmParameter(
      minimum: v['min'] as int,
      maximum: v['max'] as int,
      defaultValue: v['default'] as int,
      label: v['label'] as String);
}

class FilmDefinition {
  FilmDefinition.fromJson(Map<String, dynamic> v)
      : id = v['id'] as int,
        name = v['name'] as String,
        group = v['group'] as String,
        icon = v['icon'] as String,
        parameters = Map.unmodifiable((v['parameters'] as Map).map((k, p) =>
            MapEntry(k as String,
                FilmParameter.fromJson(Map<String, dynamic>.from(p as Map)))));
  final int id;
  final String name, group, icon;
  final Map<String, FilmParameter> parameters;
}

class FilmCatalog {
  FilmCatalog.fromJson(Map<String, dynamic> v)
      : hash = v['hash'] as String,
        rendererHash = v['rendererHash'] as String,
        entries = List.unmodifiable((v['entries'] as List).map((f) =>
            FilmDefinition.fromJson(Map<String, dynamic>.from(f as Map)))) {
    if (v['schemaVersion'] != 1 ||
        entries.map((e) => e.id).toSet().length != entries.length) {
      throw const FormatException('胶卷目录不受支持');
    }
  }
  final String hash, rendererHash;
  final List<FilmDefinition> entries;
  FilmDefinition film(int id) => entries.firstWhere((e) => e.id == id,
      orElse: () => throw const FormatException('胶卷不在当前目录中'));
  FilmRecipe recipe(int id,
      {String? name, Map<String, int> parameters = const {}}) {
    final f = film(id);
    return FilmRecipe.fromJson({
      'schemaVersion': 1,
      'filmId': id,
      'catalogHash': hash,
      'rendererHash': rendererHash,
      'name': name ?? f.name,
      'parameters': {
        for (final e in f.parameters.entries) e.key: e.value.defaultValue,
        ...parameters
      }
    });
  }
}
