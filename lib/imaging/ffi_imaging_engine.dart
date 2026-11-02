import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'imaging_bindings.dart';
import 'imaging_engine.dart';
import 'imaging_exception.dart';

/// Runs the C++ imaging core on background isolates.
class FfiImagingEngine implements ImagingEngine {
  FfiImagingEngine({String libraryPath = 'libgremote_imaging.so'})
      : _libraryPath = libraryPath;

  final String _libraryPath;

  @override
  Future<int> validateLut(Uint8List cube) {
    final path = _libraryPath;
    return Isolate.run(() => _validateLut(path, cube));
  }

  @override
  Future<PreviewImage> decodePreview({
    required int fd,
    required int orientation,
    required int maxEdge,
  }) {
    final path = _libraryPath;
    return Isolate.run(() => _decodePreview(path, fd, orientation, maxEdge));
  }

  @override
  Future<PreviewImage> applyLut(
      PreviewImage source, Uint8List cube, double strength) {
    final path = _libraryPath;
    return Isolate.run(() => _applyLut(path, source, cube, strength));
  }

  @override
  Future<PreviewImage> renderPhoto(
    PreviewImage source, {
    required Float32List adjustments,
    Uint8List? cube,
    double strength = 1,
    required int width,
    required int height,
  }) {
    final path = _libraryPath;
    return Isolate.run(() =>
        _renderPhoto(path, source, adjustments, cube, strength, width, height));
  }

  @override
  Future<void> exportJpeg(ExportJob job, {ImagingCancelToken? cancel}) {
    final path = _libraryPath;
    final cancelAddress = cancel?.address ?? 0;
    return Isolate.run(() => _export(path, job, cancelAddress));
  }
}

void _check(int status) {
  if (status != 0) throw ImagingException(ImagingErrorCode.fromValue(status));
}

Pointer<Uint8> _copy(Arena arena, Uint8List bytes) {
  final pointer = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  pointer.asTypedList(bytes.length).setAll(0, bytes);
  return pointer;
}

Pointer<Float> _copyEdits(Arena arena, Float32List edits) {
  final pointer = arena<Float>(edits.isEmpty ? 1 : edits.length);
  pointer.asTypedList(edits.length).setAll(0, edits);
  return pointer;
}

int _rgbaLength(int width, int height) {
  // Check before passing dimensions through the signed int32 ABI or copying
  // source bytes. The pixel cap matches the native image allocation limit.
  if (width <= 0 || height <= 0 || width > 0x7fffffff || height > 0x7fffffff) {
    throw const ImagingException(ImagingErrorCode.invalidArgument);
  }
  final pixels = width * height;
  if (pixels > 100000000) {
    throw const ImagingException(ImagingErrorCode.tooLarge);
  }
  return pixels * 4;
}

PreviewImage _renderPhoto(
  String path,
  PreviewImage source,
  Float32List adjustments,
  Uint8List? cube,
  double strength,
  int width,
  int height,
) {
  final sourceLength = _rgbaLength(source.width, source.height);
  final outputLength = _rgbaLength(width, height);
  if (source.rgba.length != sourceLength ||
      adjustments.length != 1062 ||
      adjustments.any((value) => !value.isFinite) ||
      !strength.isFinite) {
    throw const ImagingException(ImagingErrorCode.invalidArgument);
  }
  final bindings = ImagingBindings.open(path);
  return using((arena) {
    final output = arena<Pointer<Uint8>>()..value = nullptr;
    try {
      _check(bindings.renderPhoto(
        _copy(arena, source.rgba),
        source.width,
        source.height,
        _copyEdits(arena, adjustments),
        adjustments.length,
        cube == null || cube.isEmpty ? nullptr : _copy(arena, cube),
        cube?.length ?? 0,
        strength,
        width,
        height,
        output,
      ));
      if (output.value == nullptr) {
        throw const ImagingException(ImagingErrorCode.outOfMemory);
      }
      return PreviewImage(
        width: width,
        height: height,
        rgba: Uint8List.fromList(output.value.asTypedList(outputLength)),
      );
    } finally {
      // Native owns this allocation, including any buffer returned on failure.
      bindings.free(output.value.cast());
    }
  });
}

int _validateLut(String path, Uint8List cube) {
  if (cube.isEmpty) throw const ImagingException(ImagingErrorCode.lutParse);
  final bindings = ImagingBindings.open(path);
  return using((arena) {
    final size = arena<Int32>();
    _check(bindings.lutValidate(_copy(arena, cube), cube.length, size));
    return size.value;
  });
}

PreviewImage _decodePreview(String path, int fd, int orientation, int maxEdge) {
  final bindings = ImagingBindings.open(path);
  return using((arena) {
    final rgba = arena<Pointer<Uint8>>();
    final width = arena<Int32>();
    final height = arena<Int32>();
    _check(
        bindings.decodePreview(fd, orientation, maxEdge, rgba, width, height));
    try {
      final length = width.value * height.value * 4;
      return PreviewImage(
        width: width.value,
        height: height.value,
        rgba: Uint8List.fromList(rgba.value.asTypedList(length)),
      );
    } finally {
      bindings.free(rgba.value.cast());
    }
  });
}

PreviewImage _applyLut(
    String path, PreviewImage source, Uint8List cube, double strength) {
  if (cube.isEmpty) throw const ImagingException(ImagingErrorCode.lutParse);
  final bindings = ImagingBindings.open(path);
  return using((arena) {
    final pixels = _copy(arena, source.rgba);
    _check(bindings.applyLut(pixels, source.width, source.height,
        _copy(arena, cube), cube.length, strength));
    return PreviewImage(
      width: source.width,
      height: source.height,
      rgba: Uint8List.fromList(pixels.asTypedList(source.rgba.length)),
    );
  });
}

void _export(String path, ExportJob job, int cancelAddress) {
  final bindings = ImagingBindings.open(path);
  using((arena) {
    final request = arena<NativeExportRequest>();
    final cube = job.cube;
    final adjustments = job.adjustments;
    final overlays = job.overlays.isEmpty
        ? nullptr
        : arena<NativeOverlay>(job.overlays.length);
    for (var i = 0; i < job.overlays.length; i++) {
      final source = job.overlays[i];
      overlays[i]
        ..x = source.x
        ..y = source.y
        ..width = source.width
        ..height = source.height
        ..rgba = _copy(arena, source.rgba);
    }
    request.ref
      ..fd = job.fd
      ..orientation = job.orientation
      ..cube = cube == null || cube.isEmpty ? nullptr : _copy(arena, cube)
      ..cubeLength = cube?.length ?? 0
      ..lutStrength = job.lutStrength
      ..photoWidth = job.photoWidth
      ..photoHeight = job.photoHeight
      ..photoX = job.photoX
      ..photoY = job.photoY
      ..canvasWidth = job.canvasWidth
      ..canvasHeight = job.canvasHeight
      ..backgroundR = (job.background >> 16) & 0xff
      ..backgroundG = (job.background >> 8) & 0xff
      ..backgroundB = job.background & 0xff
      ..overlays = overlays
      ..overlayCount = job.overlays.length
      ..quality = job.quality
      ..outputPath = job.outputPath.toNativeUtf8(allocator: arena)
      ..edits = adjustments == null || adjustments.isEmpty
          ? nullptr
          : _copyEdits(arena, adjustments)
      ..editCount = adjustments?.length ?? 0;
    final cancel = cancelAddress == 0
        ? nullptr
        : Pointer<Int32>.fromAddress(cancelAddress);
    _check(bindings.exportJpeg(request, cancel));
  });
}
