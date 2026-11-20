import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../camera/companion/camera_live_manifest.dart';
import '../../camera/http/camera_files.dart';
import '../../platform/motion_photo_api.dart';

class PreparedCameraLivePhoto {
  const PreparedCameraLivePhoto(
      this.directory, this.jpeg, this.mp4, this.presentationTimestampUs);

  final Directory directory;
  final File jpeg;
  final File mp4;
  final int? presentationTimestampUs;

  Future<void> dispose() async {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Cache eviction may have already removed the staged inputs.
    }
  }
}

class CameraLiveMedia {
  const CameraLiveMedia(
      {this.native = const MotionPhotoApi(),
      this.temporaryDirectory = getTemporaryDirectory});

  final MotionPhotoApi native;
  final Future<Directory> Function() temporaryDirectory;

  Future<PreparedCameraLivePhoto?> prepare(CameraLiveApi api, CameraFile photo,
      {required bool Function() isCurrent}) async {
    final manifest = await api.liveManifest(photo);
    if (manifest == null || !isCurrent()) return null;
    final dir = await (await temporaryDirectory()).createTemp('gremote-live-');
    final jpeg = File('${dir.path}/still.jpg');
    final mp4 = File('${dir.path}/motion.mp4');
    final input = manifest.format == CameraClipFormat.mp4
        ? mp4
        : File('${dir.path}/motion.m10l');
    var ready = false;
    try {
      if (!isCurrent()) return null;
      await native.downloadJpeg(
        directory: photo.dir,
        file: photo.file,
        jpegPath: jpeg.path,
        sha256: manifest.jpegSha256,
      );
      if (!isCurrent()) return null;
      final sink = await input.open(mode: FileMode.write);
      try {
        await api.liveClip(manifest, (chunk) async {
          if (!isCurrent()) throw const _PreparationCancelled();
          await sink.writeFrom(chunk);
        });
      } on _PreparationCancelled {
        return null;
      } finally {
        await sink.close();
      }
      if (!isCurrent()) return null;
      if (await input.length() != manifest.clipBytes ||
          (await sha256.bind(input.openRead()).first).toString() !=
              manifest.clipSha256) {
        throw const FormatException('动态短片校验失败，请重新从相机读取');
      }
      var timestamp = manifest.presentationTimestampUs;
      if (manifest.format == CameraClipFormat.m10l) {
        timestamp = await native.transcodeM10l(input.path, mp4.path, timestamp);
      }
      if (!isCurrent()) return null;
      ready = true;
      return PreparedCameraLivePhoto(dir, jpeg, mp4, timestamp);
    } finally {
      if (!ready) {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // Cache eviction may have already removed the staged inputs.
        }
      }
    }
  }
}

class _PreparationCancelled implements Exception {
  const _PreparationCancelled();
}
