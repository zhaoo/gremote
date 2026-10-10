export '../http/camera_files.dart' show baseNameOf;

import 'package:meta/meta.dart';

import '../../media/local/local_media_repository.dart';
import '../capture/capture_tracker.dart';
import '../http/camera_files.dart';
import 'recipe_store.dart';

enum MatchStrength { strong, weak }

@immutable
class TagMatch {
  const TagMatch({required this.tag, required this.strength});

  final CaptureTag tag;
  final MatchStrength strength;

  bool get usable => strength == MatchStrength.strong || tag.confirmed;
}

/// Matches by file base name first, then by camera/phone wall-clock windows.
TagMatch? matchTag(LocalMediaItem item, List<CaptureTag> tags) {
  final baseName = baseNameOf(item.displayName);
  final exifSeconds = exifWallSeconds(item.meta?.takenAt);
  final itemSeconds = exifSeconds ?? _fallbackWallSeconds(item);
  TagMatch? best;
  var bestDifference = 1 << 62;

  for (final tag in tags) {
    if (tag.baseName.toUpperCase() != baseName) continue;
    final difference = switch (tag.timeSource) {
      TimeSource.camera when exifSeconds != null =>
        (exifSeconds - tag.wallSeconds).abs(),
      TimeSource.phone when itemSeconds != null =>
        (itemSeconds - tag.wallSeconds).abs(),
      _ => null,
    };
    if (difference == null) continue;
    final strength = tag.timeSource == TimeSource.camera
        ? MatchStrength.strong
        : MatchStrength.weak;
    final limit = strength == MatchStrength.strong ? 2 : 12 * 60 * 60;
    if (difference > limit || difference >= bestDifference) continue;
    bestDifference = difference;
    best = TagMatch(tag: tag, strength: strength);
  }
  return best;
}

int? _fallbackWallSeconds(LocalMediaItem item) {
  final milliseconds = item.dateTaken ?? item.dateModified * 1000;
  if (milliseconds <= 0) return null;
  return phoneWallSeconds(DateTime.fromMillisecondsSinceEpoch(milliseconds));
}
