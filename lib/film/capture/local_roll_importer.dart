import '../../media/local/media_gateway.dart';
import '../model/camera_photo_identity.dart';
import '../model/film_recipe.dart';
import '../model/film_roll.dart';
import '../store/film_repository.dart';

class LocalRollImporter {
  const LocalRollImporter({required this.repository, required this.gateway});
  final FilmRepository repository;
  final MediaGateway gateway;
  Future<RollItem> import(
      {required String rollId,
      required int mediaId,
      required FilmRecipe recipe}) async {
    final hash = await gateway.contentHash(mediaId);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('原片校验失败');
    }
    // This is an explicitly imported local file, not a camera/card identity.
    final identity = CameraPhotoIdentity(
        instanceId: 'local-photo',
        storageId: 'photo-library',
        storageEpoch: 'sha256-v1',
        dir: 'content',
        baseName: hash,
        contentHash: hash);
    return repository.addConfirmedPhoto(
        rollId: rollId,
        identity: identity,
        recipe: recipe,
        files: ['LOCAL_${hash.substring(0, 16)}.JPG'],
        confidence: RecipeConfidence.userAssigned,
        mediaId: mediaId);
  }
}
