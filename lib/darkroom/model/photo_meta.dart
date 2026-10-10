import 'package:meta/meta.dart';

/// EXIF facts the darkroom needs about one source photo.
@immutable
class PhotoMeta {
  const PhotoMeta({
    required this.width,
    required this.height,
    this.orientation = 1,
    this.make,
    this.model,
    this.fNumber,
    this.exposureTime,
    this.iso,
    this.focal35,
    this.focal,
    this.takenAt,
    this.hasGps = false,
  });

  factory PhotoMeta.fromJson(Map<String, Object?> json) => PhotoMeta(
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
        orientation: (json['orientation'] as num?)?.toInt() ?? 1,
        make: json['make'] as String?,
        model: json['model'] as String?,
        fNumber: (json['fNumber'] as num?)?.toDouble(),
        exposureTime: (json['exposureTime'] as num?)?.toDouble(),
        iso: (json['iso'] as num?)?.toInt(),
        focal35: (json['focal35'] as num?)?.toInt(),
        focal: (json['focal'] as num?)?.toDouble(),
        takenAt: json['takenAt'] as String?,
        hasGps: json['hasGps'] == true,
      );

  /// Stored pixel size before orientation.
  final int width;
  final int height;
  final int orientation;
  final String? make;
  final String? model;
  final double? fNumber;
  final double? exposureTime;
  final int? iso;
  final int? focal35;
  final double? focal;

  /// EXIF `DateTimeOriginal`, `yyyy:MM:dd HH:mm:ss`.
  final String? takenAt;
  final bool hasGps;

  bool get _rotated => orientation >= 5 && orientation <= 8;
  int get orientedWidth => _rotated ? height : width;
  int get orientedHeight => _rotated ? width : height;

  String? get modelLabel {
    final value = model?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get focalLabel {
    final mm = focal35 != null && focal35! > 0 ? focal35!.toDouble() : focal;
    return mm == null || mm <= 0 ? null : '${mm.round()}mm';
  }

  String? get apertureLabel {
    final f = fNumber;
    if (f == null || f <= 0) return null;
    final rounded = (f * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? 'f/${rounded.toInt()}'
        : 'f/$rounded';
  }

  String? get shutterLabel {
    final t = exposureTime;
    if (t == null || t <= 0) return null;
    if (t < 1) return '1/${(1 / t).round()}s';
    final rounded = (t * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? '${rounded.toInt()}s'
        : '${rounded}s';
  }

  String? get isoLabel => iso == null || iso! <= 0 ? null : 'ISO$iso';

  String? get dateLabel {
    final match = RegExp(r'^(\d{4}):(\d{2}):(\d{2})').firstMatch(takenAt ?? '');
    return match == null
        ? null
        : '${match.group(1)}.${match.group(2)}.${match.group(3)}';
  }

  Map<String, Object?> toJson() => {
        'width': width,
        'height': height,
        'orientation': orientation,
        'make': make,
        'model': model,
        'fNumber': fNumber,
        'exposureTime': exposureTime,
        'iso': iso,
        'focal35': focal35,
        'focal': focal,
        'takenAt': takenAt,
        'hasGps': hasGps,
      };

  PhotoMeta copyWith({
    int? orientation,
    double? fNumber,
    double? exposureTime,
  }) =>
      PhotoMeta(
        width: width,
        height: height,
        orientation: orientation ?? this.orientation,
        make: make,
        model: model,
        fNumber: fNumber ?? this.fNumber,
        exposureTime: exposureTime ?? this.exposureTime,
        iso: iso,
        focal35: focal35,
        focal: focal,
        takenAt: takenAt,
        hasGps: hasGps,
      );
}
