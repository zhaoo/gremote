import 'dart:convert';
import 'dart:typed_data';

import '../http/camera_files.dart';

enum CameraClipFormat { mp4, m10l }

abstract interface class CameraLiveApi {
  Future<CameraLiveManifest?> liveManifest(CameraFile jpeg);
  Future<void> liveClip(
      CameraLiveManifest manifest, Future<void> Function(Uint8List) receive);
}

class CameraLiveManifest {
  const CameraLiveManifest._(this.jpeg, this.jpegSha256, this.format,
      this.clipBytes, this.clipSha256, this.presentationTimestampUs);

  static const maxClipBytes = 24 + 48 * (8 + 131072);
  static const maxChunkBytes = 8192;
  static final _part = RegExp(r'^[A-Za-z0-9_-]{1,16}$');
  static final _sha = RegExp(r'^[a-f0-9]{64}$');
  static final _jpeg = RegExp(r'^([A-Za-z0-9_-]{1,16})\.([Jj][Pp][Ee]?[Gg])$');

  final CameraFile jpeg;
  final String jpegSha256;
  final CameraClipFormat format;
  final int clipBytes;
  final String clipSha256;
  final int? presentationTimestampUs;

  static String pathFor(CameraFile file) {
    final name = _jpeg.firstMatch(file.file);
    if (!_matches(_part, file.dir) ||
        name == null ||
        name.end != file.file.length) {
      throw const FormatException('动态照片需对应原始 JPEG 文件');
    }
    return '/m10v/v1/live/${file.dir}/${name[1]}/${name[2]}';
  }

  static CameraLiveManifest parse(
      Map<String, dynamic> wire, CameraFile expectedJpeg) {
    final jpeg = wire['jpeg'];
    final clip = wire['clip'];
    final timestamp = wire['presentationTimestampUs'];
    if (wire['version'] is! int ||
        wire['version'] != 1 ||
        jpeg is! Map ||
        clip is! Map ||
        jpeg['directory'] != expectedJpeg.dir ||
        jpeg['file'] != expectedJpeg.file ||
        !_isSha(jpeg['sha256']) ||
        !_isSha(clip['sha256']) ||
        (timestamp != null && (timestamp is! int || timestamp < 0))) {
      throw const FormatException('动态照片配对信息无效');
    }
    final format = switch (clip['format']) {
      'mp4' => CameraClipFormat.mp4,
      'm10l' => CameraClipFormat.m10l,
      _ => throw const FormatException('动态短片格式不受支持'),
    };
    final directory = clip['directory'];
    final clipFile = clip['file'];
    final validClipFile = RegExp(r'^[A-Za-z0-9_-]{1,64}\.' + format.name + r'$',
        caseSensitive: false);
    final length = clip['bytes'];
    if (directory is! String ||
        !_matches(_part, directory) ||
        clipFile is! String ||
        !_matches(validClipFile, clipFile) ||
        length is! int ||
        length < (format == CameraClipFormat.m10l ? 48 : 16) ||
        length > maxClipBytes ||
        (timestamp is int &&
            format == CameraClipFormat.m10l &&
            timestamp > 4500000)) {
      throw const FormatException('动态短片名称、长度或时间无效');
    }
    return CameraLiveManifest._(expectedJpeg, jpeg['sha256'] as String, format,
        length, clip['sha256'] as String, timestamp as int?);
  }

  Uint8List chunk(Map<String, dynamic> wire, int expectedOffset) {
    final data = wire['data'];
    if (wire['offset'] is! int ||
        wire['offset'] != expectedOffset ||
        wire['bytes'] is! int ||
        wire['bytes'] != clipBytes ||
        data is! String ||
        data.length > ((maxChunkBytes + 2) ~/ 3) * 4) {
      throw const FormatException('动态短片传输内容已变化');
    }
    final decoded = base64Decode(data);
    if (decoded.isEmpty ||
        decoded.length > maxChunkBytes ||
        decoded.length > clipBytes - expectedOffset) {
      throw const FormatException('动态短片分段长度无效');
    }
    return decoded;
  }

  static bool _isSha(Object? value) => value is String && _matches(_sha, value);

  static bool _matches(RegExp pattern, String value) =>
      pattern.firstMatch(value)?.end == value.length;
}
