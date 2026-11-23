import 'package:flutter/services.dart';

class MotionVideoPlayer {
  const MotionVideoPlayer(
      this.textureId, this.width, this.height, this.durationMs);
  final int textureId, width, height, durationMs;
}

class MotionVideoInfo {
  const MotionVideoInfo(this.durationMs, this.frames);
  final int durationMs;
  final List<Uint8List> frames;
}

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

  Future<MotionVideoPlayer> openPlayer(String mp4Path) async {
    final value = await _channel
        .invokeMapMethod<String, Object?>('openPlayer', {'mp4Path': mp4Path});
    if (value == null ||
        value['textureId'] is! int ||
        value['durationMs'] is! int ||
        value['width'] is! int ||
        value['height'] is! int) {
      throw const FormatException('播放器未准备完成');
    }
    return MotionVideoPlayer(value['textureId'] as int, value['width'] as int,
        value['height'] as int, value['durationMs'] as int);
  }

  Future<MotionVideoInfo> inspectVideo(String mp4Path) async {
    final value = await _channel
        .invokeMapMethod<String, Object?>('inspectVideo', {'mp4Path': mp4Path});
    final frames = value?['frames'];
    if (value?['durationMs'] is! int ||
        frames is! List ||
        frames.any((frame) => frame is! Uint8List)) {
      throw const FormatException('短片预览未准备完成');
    }
    return MotionVideoInfo(
        value!['durationMs'] as int, frames.cast<Uint8List>());
  }

  Future<Map<String, Object?>> playerControl(int textureId, String action,
          {int? positionMs}) async =>
      await _channel.invokeMapMethod<String, Object?>('playerControl', {
        'textureId': textureId,
        'action': action,
        if (positionMs != null) 'positionMs': positionMs
      }) ??
      const {};

  Future<Map<String, Object?>> playerStatus(int textureId) async =>
      await _channel.invokeMapMethod<String, Object?>(
          'playerStatus', {'textureId': textureId}) ??
      const {};

  Future<String> exportVideo(String mp4Path, String displayName) async {
    final uri = await _channel.invokeMethod<String>(
        'exportVideo', {'mp4Path': mp4Path, 'displayName': displayName});
    if (uri == null || uri.isEmpty) throw const FormatException('视频未保存');
    return uri;
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
