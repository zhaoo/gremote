import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class NativeOverlay extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Int32()
  external int width;
  @Int32()
  external int height;
  external Pointer<Uint8> rgba;
}

final class NativeExportRequest extends Struct {
  @Int32()
  external int fd;
  @Int32()
  external int orientation;
  external Pointer<Uint8> cube;
  @Int64()
  external int cubeLength;
  @Float()
  external double lutStrength;
  @Int32()
  external int photoWidth;
  @Int32()
  external int photoHeight;
  @Int32()
  external int photoX;
  @Int32()
  external int photoY;
  @Int32()
  external int canvasWidth;
  @Int32()
  external int canvasHeight;
  @Uint8()
  external int backgroundR;
  @Uint8()
  external int backgroundG;
  @Uint8()
  external int backgroundB;
  external Pointer<NativeOverlay> overlays;
  @Int32()
  external int overlayCount;
  @Int32()
  external int quality;
  external Pointer<Utf8> outputPath;
}

typedef _DecodePreviewC = Int32 Function(Int32, Int32, Int32,
    Pointer<Pointer<Uint8>>, Pointer<Int32>, Pointer<Int32>);
typedef DecodePreviewFn = int Function(
    int, int, int, Pointer<Pointer<Uint8>>, Pointer<Int32>, Pointer<Int32>);
typedef _LutValidateC = Int32 Function(Pointer<Uint8>, Int64, Pointer<Int32>);
typedef LutValidateFn = int Function(Pointer<Uint8>, int, Pointer<Int32>);
typedef _ApplyLutC = Int32 Function(
    Pointer<Uint8>, Int32, Int32, Pointer<Uint8>, Int64, Float);
typedef ApplyLutFn = int Function(
    Pointer<Uint8>, int, int, Pointer<Uint8>, int, double);
typedef _ExportC = Int32 Function(Pointer<NativeExportRequest>, Pointer<Int32>);
typedef ExportFn = int Function(Pointer<NativeExportRequest>, Pointer<Int32>);
typedef _FreeC = Void Function(Pointer<Void>);
typedef FreeFn = void Function(Pointer<Void>);

/// Thin lookup of the C ABI in `native/imaging/include/gremote_imaging.h`.
class ImagingBindings {
  ImagingBindings(DynamicLibrary library)
      : decodePreview =
            library.lookupFunction<_DecodePreviewC, DecodePreviewFn>(
                'gremote_decode_preview'),
        lutValidate = library.lookupFunction<_LutValidateC, LutValidateFn>(
            'gremote_lut_validate'),
        applyLut = library
            .lookupFunction<_ApplyLutC, ApplyLutFn>('gremote_apply_lut_rgba'),
        exportJpeg =
            library.lookupFunction<_ExportC, ExportFn>('gremote_export_jpeg'),
        free = library.lookupFunction<_FreeC, FreeFn>('gremote_free');

  factory ImagingBindings.open(String path) =>
      ImagingBindings(DynamicLibrary.open(
          Platform.isIOS ? 'gremote_imaging.framework/gremote_imaging' : path));

  final DecodePreviewFn decodePreview;
  final LutValidateFn lutValidate;
  final ApplyLutFn applyLut;
  final ExportFn exportJpeg;
  final FreeFn free;
}
