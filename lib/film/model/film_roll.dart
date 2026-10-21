import 'film_recipe.dart';
import 'camera_photo_identity.dart';

enum FilmRollStatus { open, closed, archived }

enum RecipeConfidence { cameraConfirmed, userAssigned, unverified }

class FilmRoll {
  const FilmRoll(
      {required this.id,
      required this.name,
      required this.targetCount,
      required this.recipeFingerprint,
      required this.status,
      required this.createdAt,
      this.closedAt,
      this.confirmedCount = 0});
  final String id, name, recipeFingerprint;
  final int targetCount, confirmedCount;
  final FilmRollStatus status;
  final DateTime createdAt;
  final DateTime? closedAt;
}

class RollItem {
  RollItem(
      {required this.id,
      required this.rollId,
      required this.identity,
      required this.recipe,
      required List<String> files,
      required this.confidence,
      required this.createdAt,
      this.mediaId,
      this.selected = false})
      : files = List.unmodifiable(files);
  final String id, rollId;
  final CameraPhotoIdentity identity;
  final FilmRecipe recipe;
  final List<String> files;
  final RecipeConfidence confidence;
  final DateTime createdAt;
  final int? mediaId;
  final bool selected;
}
