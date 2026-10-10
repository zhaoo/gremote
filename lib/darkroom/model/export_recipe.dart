import 'package:meta/meta.dart';

enum FrameStyle {
  classic('经典白边'),
  street('街拍暗金'),
  contact('胶片印样');

  const FrameStyle(this.label);
  final String label;
}

enum FrameRatio {
  original('原比例', null),
  portrait3x4('3:4', (3, 4)),
  portrait4x5('4:5', (4, 5)),
  square('1:1', (1, 1));

  const FrameRatio(this.label, this.aspect);
  final String label;

  /// Canvas width:height, or null to follow the frame margins.
  final (int, int)? aspect;
}

enum ExportSize {
  original('原始尺寸', null),
  long2560('长边 2560', 2560),
  long1440('长边 1440', 1440);

  const ExportSize(this.label, this.longEdge);
  final String label;
  final int? longEdge;
}

const exportQualities = [85, 90, 95, 100];

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

@immutable
class ExportRecipe {
  const ExportRecipe({
    this.lutId,
    this.strength = 1,
    this.frame = FrameStyle.classic,
    this.ratio = FrameRatio.original,
    this.size = ExportSize.original,
    this.quality = 95,
    this.keepGps = false,
  });

  factory ExportRecipe.fromJson(Map<String, Object?> json) {
    final strength = json['strength'];
    final quality = json['quality'];
    final lutId = json['lutId'];
    return ExportRecipe(
      lutId: lutId is String && lutId.isNotEmpty ? lutId : null,
      strength: strength is num && strength >= 0 && strength <= 1
          ? strength.toDouble()
          : 1,
      frame: _enumByName(FrameStyle.values, json['frame'], FrameStyle.classic),
      ratio: _enumByName(FrameRatio.values, json['ratio'], FrameRatio.original),
      size: _enumByName(ExportSize.values, json['size'], ExportSize.original),
      quality: exportQualities.contains(quality) ? quality! as int : 95,
      keepGps: json['keepGps'] == true,
    );
  }

  final String? lutId;
  final double strength;
  final FrameStyle frame;
  final FrameRatio ratio;
  final ExportSize size;
  final int quality;
  final bool keepGps;

  Map<String, Object?> toJson() => {
        'lutId': lutId,
        'strength': strength,
        'frame': frame.name,
        'ratio': ratio.name,
        'size': size.name,
        'quality': quality,
        'keepGps': keepGps,
      };

  ExportRecipe copyWith({
    String? Function()? lutId,
    double? strength,
    FrameStyle? frame,
    FrameRatio? ratio,
    ExportSize? size,
    int? quality,
    bool? keepGps,
  }) =>
      ExportRecipe(
        lutId: lutId == null ? this.lutId : lutId(),
        strength: strength ?? this.strength,
        frame: frame ?? this.frame,
        ratio: ratio ?? this.ratio,
        size: size ?? this.size,
        quality: quality ?? this.quality,
        keepGps: keepGps ?? this.keepGps,
      );

  @override
  bool operator ==(Object other) =>
      other is ExportRecipe &&
      other.lutId == lutId &&
      other.strength == strength &&
      other.frame == frame &&
      other.ratio == ratio &&
      other.size == size &&
      other.quality == quality &&
      other.keepGps == keepGps;

  @override
  int get hashCode =>
      Object.hash(lutId, strength, frame, ratio, size, quality, keepGps);
}
