import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

class PreviewImage {
  const PreviewImage({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;
}

@immutable
class ExportOverlay {
  const ExportOverlay({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  /// Straight-alpha RGBA8, `width * height * 4` bytes.
  final Uint8List rgba;
}

@immutable
class ExportJob {
  const ExportJob({
    required this.fd,
    required this.orientation,
    required this.photoWidth,
    required this.photoHeight,
    required this.photoX,
    required this.photoY,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.background,
    required this.quality,
    required this.outputPath,
    this.cube,
    this.lutStrength = 1,
    this.overlays = const [],
  });

  /// Read-only descriptor; the engine always closes it.
  final int fd;
  final int orientation;
  final Uint8List? cube;
  final double lutStrength;
  final int photoWidth;
  final int photoHeight;
  final int photoX;
  final int photoY;
  final int canvasWidth;
  final int canvasHeight;

  /// ARGB colour; alpha is ignored.
  final int background;
  final List<ExportOverlay> overlays;
  final int quality;
  final String outputPath;
}

/// Cancellation flag shared with native code across isolates.
class ImagingCancelToken {
  ImagingCancelToken() : _flag = calloc<Int32>();

  final Pointer<Int32> _flag;
  bool _disposed = false;

  int get address => _flag.address;
  bool get isCancelled => !_disposed && _flag.value != 0;

  void cancel() {
    if (!_disposed) _flag.value = 1;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    calloc.free(_flag);
  }
}

abstract interface class ImagingEngine {
  /// Returns the LUT grid size.
  Future<int> validateLut(Uint8List cube);

  Future<PreviewImage> decodePreview({
    required int fd,
    required int orientation,
    required int maxEdge,
  });

  /// Returns a mapped copy; [source] is untouched.
  Future<PreviewImage> applyLut(
      PreviewImage source, Uint8List cube, double strength);

  Future<void> exportJpeg(ExportJob job, {ImagingCancelToken? cancel});
}
