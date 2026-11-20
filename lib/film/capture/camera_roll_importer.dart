import '../../camera/http/camera_files.dart';
import '../../camera/recipe/shooting_recipe.dart';
import '../model/camera_roll_frame.dart';
import '../model/film_roll.dart';
import '../store/film_repository.dart';

export '../model/camera_roll_frame.dart';

class CameraRollImporter {
  const CameraRollImporter(this.repository);

  final FilmRepository repository;

  Future<RollItem> import(CameraFile file, CameraRollFrame frame,
      {required String hash, int? mediaId, int? filmCode, String? recipe}) {
    final film = RecordedExposure.parse(recipe, filmCode)?.toFilmRecipe();
    return repository.importCameraFrame(file, frame,
        hash: hash, mediaId: mediaId, recipe: film);
  }
}
