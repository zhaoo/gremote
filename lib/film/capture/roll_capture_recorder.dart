import '../../camera/capture/capture_tracker.dart';
import '../model/camera_photo_identity.dart';
import '../model/film_recipe.dart';
import '../model/film_roll.dart';
import '../store/film_repository.dart';

class RecipeEvidence {
  const RecipeEvidence(
      {required this.rollId,
      required this.recipe,
      required this.identity,
      required this.sessionGeneration,
      required this.confidence});
  final String rollId;
  final FilmRecipe recipe;
  final CameraPhotoIdentity identity;
  final int sessionGeneration;
  final RecipeConfidence confidence;
}

class RollCaptureRecorder {
  RollCaptureRecorder(this.repository, {required this.generation});
  final FilmRepository repository;
  final int Function() generation;
  final _known = <String, RecipeEvidence>{};
  Future<void> record(CaptureRecord record, RecipeEvidence evidence) async {
    if (record.files.isEmpty ||
        evidence.sessionGeneration != generation() ||
        !evidence.identity.isStable ||
        record.dir != evidence.identity.dir ||
        record.baseName.toUpperCase() !=
            evidence.identity.baseName.toUpperCase()) return;
    try {
      await repository.addConfirmedPhoto(
          rollId: evidence.rollId,
          identity: evidence.identity,
          recipe: evidence.recipe,
          files: record.files,
          confidence: evidence.confidence,
          isCurrent: () => evidence.sessionGeneration == generation());
    } on StateError {
      if (evidence.sessionGeneration != generation()) return;
      rethrow;
    }
    _known['${record.dir}/${record.baseName.toUpperCase()}'] = evidence;
    while (_known.length > 256) {
      _known.remove(_known.keys.first);
    }
  }

  Future<void> appendFiles(CaptureFileUpdate update) async {
    final evidence = _known['${update.dir}/${update.baseName.toUpperCase()}'];
    if (evidence == null || evidence.sessionGeneration != generation()) return;
    await repository.addConfirmedPhoto(
        rollId: evidence.rollId,
        identity: evidence.identity,
        recipe: evidence.recipe,
        files: update.files,
        confidence: evidence.confidence,
        isCurrent: () => evidence.sessionGeneration == generation());
  }

  void clear() => _known.clear();
}
