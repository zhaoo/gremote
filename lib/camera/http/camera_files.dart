import 'package:meta/meta.dart';

/// One file listed by `GET /v1/photos`.
@immutable
class CameraFile {
  const CameraFile({required this.dir, required this.file});

  final String dir;
  final String file;

  /// File name without extension, e.g. `R0001234`; RAW+JPEG pairs share it.
  String get baseName => baseNameOf(file);

  String get extension {
    final dot = file.lastIndexOf('.');
    return dot < 0 ? '' : file.substring(dot + 1).toUpperCase();
  }

  String get remoteId => '$dir/$file';

  bool get downloadable =>
      extension == 'JPG' || extension == 'JPEG' || extension == 'DNG';

  @override
  bool operator ==(Object other) =>
      other is CameraFile && other.dir == dir && other.file == file;

  @override
  int get hashCode => Object.hash(dir, file);

  @override
  String toString() => remoteId;
}

String baseNameOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return (dot < 0 ? fileName : fileName.substring(0, dot)).toUpperCase();
}

/// Parses `{"dirs":[{"name":"100RICOH","files":["R0000001.JPG"]}]}`
/// (firmware-derived / hardware-unverified).
List<CameraFile> parsePhotoList(Map<String, Object?> json) {
  final dirs = json['dirs'];
  if (dirs is! List) return const [];
  return [
    for (final dir in dirs)
      if (dir case {'name': final String name, 'files': final List files})
        for (final file in files)
          if (file is String) CameraFile(dir: name, file: file),
  ];
}

const _infoTimeKeys = ['datetime', 'dateTime', 'captureDate', 'date'];

/// Capture time from `/v1/photos/<dir>/<file>/info` as wall-clock seconds.
int? parseCaptureWallSeconds(Map<String, Object?> info) {
  for (final key in _infoTimeKeys) {
    final value = info[key];
    if (value is String) {
      final seconds = wallSecondsOf(value);
      if (seconds != null) return seconds;
    }
  }
  return null;
}

/// EXIF `DateTimeOriginal` (`2026:10:10 08:30:00`) as wall-clock seconds.
int? exifWallSeconds(String? takenAt) =>
    takenAt == null ? null : wallSecondsOf(takenAt);

final _dateTime =
    RegExp(r'^(\d{4})[-:](\d{2})[-:](\d{2})[T ](\d{2}):(\d{2}):(\d{2})');

/// Wall-clock seconds: local date fields read as if they were UTC, so camera
/// and EXIF times compare without time-zone conversions.
int? wallSecondsOf(String text) {
  final match = _dateTime.firstMatch(text.trim());
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  return DateTime.utc(
              parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
          .millisecondsSinceEpoch ~/
      1000;
}

/// The phone's wall clock in the same scale as [wallSecondsOf].
int phoneWallSeconds([DateTime? now]) {
  final t = (now ?? DateTime.now()).toLocal();
  return DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second)
          .millisecondsSinceEpoch ~/
      1000;
}
