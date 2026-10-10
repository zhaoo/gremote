import 'dart:convert';

import 'package:meta/meta.dart';

import 'export_recipe.dart';

enum FrameField {
  model('机型'),
  focal('焦距'),
  aperture('光圈'),
  shutter('快门'),
  iso('ISO'),
  date('日期'),
  title('标题'),
  location('地点');

  const FrameField(this.label);
  final String label;
}

@immutable
class EditDocument {
  const EditDocument({
    required this.mediaId,
    required this.updatedAt,
    this.recipe = const ExportRecipe(),
    this.title = '',
    this.location = '',
    this.hidden = const {},
  });

  factory EditDocument.fromJsonParts({
    required int mediaId,
    required String recipeJson,
    required String title,
    required String location,
    required String hiddenJson,
    required DateTime updatedAt,
  }) {
    final names = (jsonDecode(hiddenJson) as List).cast<String>().toSet();
    return EditDocument(
      mediaId: mediaId,
      recipe: ExportRecipe.fromJson(
          (jsonDecode(recipeJson) as Map).cast<String, Object?>()),
      title: title,
      location: location,
      hidden: FrameField.values.where((f) => names.contains(f.name)).toSet(),
      updatedAt: updatedAt,
    );
  }

  final int mediaId;
  final ExportRecipe recipe;
  final String title;
  final String location;
  final Set<FrameField> hidden;
  final DateTime updatedAt;

  String get recipeJson => jsonEncode(recipe.toJson());
  String get hiddenJson => jsonEncode([
        for (final field in FrameField.values)
          if (hidden.contains(field)) field.name
      ]);

  EditDocument copyWith({
    ExportRecipe? recipe,
    String? title,
    String? location,
    Set<FrameField>? hidden,
    DateTime? updatedAt,
  }) =>
      EditDocument(
        mediaId: mediaId,
        recipe: recipe ?? this.recipe,
        title: title ?? this.title,
        location: location ?? this.location,
        hidden: hidden ?? this.hidden,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
