import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

@immutable
class FrameStats {
  const FrameStats({required this.meanLuma, required this.histogram});

  final double meanLuma;
  final List<int> histogram;
}

abstract interface class LiveFrameAnalyzer {
  Future<FrameStats?> analyze(Uint8List jpeg);
}

final liveFrameAnalyzerProvider = Provider<LiveFrameAnalyzer>(
  (_) => const UiLiveFrameAnalyzer(),
);

/// Decodes an in-memory Live View JPEG at low resolution.
class UiLiveFrameAnalyzer implements LiveFrameAnalyzer {
  const UiLiveFrameAnalyzer();

  @override
  Future<FrameStats?> analyze(Uint8List jpeg) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(jpeg, targetWidth: 64);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return statsFromRgba(data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ));
    } on Exception {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}

/// Pure RGBA luma analysis shared by the histogram and metered ramp.
FrameStats statsFromRgba(Uint8List rgba) {
  final histogram = List<int>.filled(64, 0);
  if (rgba.isEmpty || rgba.length % 4 != 0) {
    return FrameStats(meanLuma: 0, histogram: histogram);
  }
  var sum = 0.0;
  for (var i = 0; i < rgba.length; i += 4) {
    final luma =
        (0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2]) / 255;
    sum += luma;
    histogram[(luma * 63).round().clamp(0, 63)]++;
  }
  return FrameStats(meanLuma: sum / (rgba.length ~/ 4), histogram: histogram);
}
