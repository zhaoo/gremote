import 'package:flutter/services.dart';

class MotionPhotoApi {
  const MotionPhotoApi();

  static const _channel = MethodChannel('gremote/motion_photo');

  Future<void> downloadJpeg({
    required String directory,
    required String file,
    required String jpegPath,
    required String sha256,
  }) =>
      _channel.invokeMethod<void>('downloadJpeg', {
        'directory': directory,
        'file': file,
        'jpegPath': jpegPath,
        'sha256': sha256,
      });

  Future<int> transcodeM10l(
      String inputPath, String mp4Path, int? presentationTimestampUs) async {
    final timestamp = await _channel.invokeMethod<int>('transcodeM10l', {
      'inputPath': inputPath,
      'mp4Path': mp4Path,
      'presentationTimestampUs': presentationTimestampUs,
    });
    if (timestamp == null || timestamp < 0) {
      throw const FormatException('动态短片转换未完成');
    }
    return timestamp;
  }

  Future<void> preview(String mp4Path) =>
      _channel.invokeMethod<void>('preview', {'mp4Path': mp4Path});

  Future<String> export(String jpegPath, String mp4Path, String displayName,
      {int? presentationTimestampUs}) async {
    final uri = await _channel.invokeMethod<String>('export', {
      'jpegPath': jpegPath,
      'mp4Path': mp4Path,
      'displayName': displayName,
      if (presentationTimestampUs != null)
        'presentationTimestampUs': presentationTimestampUs,
    });
    if (uri == null || uri.isEmpty) {
      throw const FormatException('动态照片未保存');
    }
    return uri;
  }
}
