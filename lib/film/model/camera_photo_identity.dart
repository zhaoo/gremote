import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'film_recipe.dart';

class CameraPhotoIdentity {
  const CameraPhotoIdentity(
      {required this.instanceId,
      required this.storageId,
      required this.storageEpoch,
      required this.dir,
      required this.baseName,
      this.captureId,
      this.contentHash});
  final String instanceId, storageId, storageEpoch, dir, baseName;
  final String? captureId, contentHash;
  bool get isStable =>
      instanceId.isNotEmpty &&
      storageId.isNotEmpty &&
      storageEpoch.isNotEmpty &&
      dir.isNotEmpty &&
      baseName.isNotEmpty &&
      ((captureId?.isNotEmpty ?? false) || (contentHash?.isNotEmpty ?? false));
  Map<String, Object?> toJson() => {
        'instanceId': instanceId,
        'storageId': storageId,
        'storageEpoch': storageEpoch,
        'dir': dir,
        'baseName': baseName.toUpperCase(),
        'captureId': captureId,
        'contentHash': contentHash
      };
  String get key =>
      sha256.convert(utf8.encode(canonicalJson(toJson()))).toString();
  factory CameraPhotoIdentity.fromJson(Map<String, dynamic> v) =>
      CameraPhotoIdentity(
          instanceId: v['instanceId'] as String,
          storageId: v['storageId'] as String,
          storageEpoch: v['storageEpoch'] as String,
          dir: v['dir'] as String,
          baseName: v['baseName'] as String,
          captureId: v['captureId'] as String?,
          contentHash: v['contentHash'] as String?);
}
