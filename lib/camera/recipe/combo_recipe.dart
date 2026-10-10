import 'package:meta/meta.dart';

@immutable
class ComboRecipe {
  const ComboRecipe({
    required this.id,
    required this.name,
    required this.sort,
    required this.createdAt,
    this.effect,
    this.exportPresetId,
  });

  static final factory = ComboRecipe(
    id: 'factory',
    name: '原厂',
    sort: -1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  final String id;
  final String name;
  final String? effect;
  final String? exportPresetId;
  final int sort;
  final DateTime createdAt;

  bool get isFactory => id == factory.id;
}
