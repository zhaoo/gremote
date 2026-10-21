import '../../camera/http/camera_files.dart';
import '../model/camera_photo_identity.dart';
import '../model/film_recipe.dart';
import '../model/film_roll.dart';
import '../store/film_repository.dart';

class CameraPhotoBaseline {
  CameraPhotoBaseline(
      {required this.instanceId,
      required this.storageId,
      required this.storageEpoch,
      required List<CameraFile> files})
      : files = List.unmodifiable(files);
  final String instanceId, storageId, storageEpoch;
  final List<CameraFile> files;
}

class UnassignedPhoto {
  UnassignedPhoto({required this.identity, required List<String> files})
      : files = List.unmodifiable(files);
  final CameraPhotoIdentity identity;
  final List<String> files;
}

abstract final class RollReconciliation {
  static List<UnassignedPhoto> candidates(
      {required CameraPhotoBaseline before, required List<CameraFile> after}) {
    String key(CameraFile f) => '${f.dir}/${f.baseName}';
    final known = before.files.map(key).toSet(),
        groups = <String, List<CameraFile>>{};
    for (final file in after) {
      if (!known.contains(key(file))) {
        groups.putIfAbsent(key(file), () => []).add(file);
      }
    }
    return [
      for (final files in groups.values)
        UnassignedPhoto(
            identity: CameraPhotoIdentity(
                instanceId: before.instanceId,
                storageId: before.storageId,
                storageEpoch: before.storageEpoch,
                dir: files.first.dir,
                baseName: files.first.baseName),
            files: files.map((f) => f.file).toList())
    ];
  }

  static Future<void> assign(List<UnassignedPhoto> photos, String rollId,
      FilmRecipe recipe, FilmRepository repository) async {
    for (final photo in photos) {
      if (!photo.identity.isStable) {
        throw const FormatException('请先读取照片身份或导入原片，再确认归档');
      }
      await repository.addConfirmedPhoto(
          rollId: rollId,
          identity: photo.identity,
          recipe: recipe,
          files: photo.files,
          confidence: RecipeConfidence.userAssigned);
    }
  }
}
