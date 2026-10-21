import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../../imaging/imaging_engine.dart';
import '../../imaging/imaging_exception.dart';
import '../model/film_recipe.dart';

enum PreviewStage { color, full }

class FilmPreviewResult {
  const FilmPreviewResult(
      {required this.image,
      required this.recipeFingerprint,
      required this.generation,
      required this.stage,
      this.bypassed = false});
  final PreviewImage image;
  final String recipeFingerprint;
  final int generation;
  final PreviewStage stage;
  final bool bypassed;
}

abstract interface class FilmPreviewEngine {
  Future<FilmPreviewResult> render(
      {required PreviewImage source,
      required FilmRecipe recipe,
      required PreviewStage stage,
      required int generation,
      ImagingCancelToken? cancel,
      int maxEdge = 960});
}

typedef _PreviewC = Int32 Function(Pointer<Uint8>, Uint32, Uint32, Uint32,
    Pointer<Uint8>, Uint32, Uint32, Pointer<Uint8>, Pointer<Int32>);
typedef _PreviewDart = int Function(Pointer<Uint8>, int, int, int,
    Pointer<Uint8>, int, int, Pointer<Uint8>, Pointer<Int32>);

class FfiFilmPreviewEngine implements FilmPreviewEngine {
  const FfiFilmPreviewEngine({this.libraryPath = 'libgremote_imaging.so'});
  final String libraryPath;
  @override
  Future<FilmPreviewResult> render(
      {required PreviewImage source,
      required FilmRecipe recipe,
      required PreviewStage stage,
      required int generation,
      ImagingCancelToken? cancel,
      int maxEdge = 960}) {
    final path = libraryPath,
        address = cancel?.address ?? 0,
        encoded = encodeFilmRecipe(recipe),
        fingerprint = recipe.fingerprint;
    if (source.width < 1 ||
        source.height < 1 ||
        source.rgba.length != source.width * source.height * 4 ||
        source.rgba.length > 8 * 1024 * 1024) {
      throw const ImagingException(ImagingErrorCode.tooLarge);
    }
    return Isolate.run(() => _render(path, source, encoded, stage, generation,
        address, maxEdge, fingerprint));
  }
}

Uint8List encodeFilmRecipe(FilmRecipe recipe) {
  final p = recipe.parameters, r = Uint8List(16);
  ByteData.sublistView(r).setUint16(0, recipe.filmId, Endian.little);
  r[2] = p['grain'] ?? 0;
  r[3] = p['grainSize'] ?? 1;
  r[4] = p['haloGain'] ?? 0;
  r[5] = p['haloSpread'] ?? 3;
  r[6] = p['haloThreshold'] ?? 5;
  r[7] = p['haloProfile'] ?? 0;
  r[8] = p['leakGain'] ?? 0;
  r[9] = p['leakPosition'] ?? 0;
  r[10] = p['leakSpread'] ?? 4;
  r[11] = p['leakVariation'] ?? 0;
  r[12] = p['filmExposure'] ?? 0;
  r[13] = p['charmeraColor'] ?? 0;
  return r;
}

FilmPreviewResult _render(
    String path,
    PreviewImage source,
    Uint8List recipe,
    PreviewStage stage,
    int generation,
    int cancelAddress,
    int maxEdge,
    String fingerprint) {
  final edge = maxEdge.clamp(1, 960),
      scale = math.min(1.0, edge / math.max(source.width, source.height));
  final width = math.max(1, (source.width * scale).round()),
      height = math.max(1, (source.height * scale).round());
  var pixels = source.rgba;
  if (width != source.width || height != source.height) {
    pixels = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final original = ((y * source.height ~/ height) * source.width +
                x * source.width ~/ width) *
            4;
        pixels.setRange((y * width + x) * 4, (y * width + x) * 4 + 4,
            source.rgba, original);
      }
    }
  }
  final library = DynamicLibrary.open(
      Platform.isIOS ? 'gremote_imaging.framework/gremote_imaging' : path);
  final render =
      library.lookupFunction<_PreviewC, _PreviewDart>('gr_film_preview_v1');
  return using((arena) {
    final input = arena<Uint8>(pixels.length)
      ..asTypedList(pixels.length).setAll(0, pixels);
    final nativeRecipe = arena<Uint8>(16)..asTypedList(16).setAll(0, recipe);
    final output = arena<Uint8>(pixels.length);
    final status = render(
        input,
        width,
        height,
        width * 4,
        nativeRecipe,
        16,
        stage == PreviewStage.color ? 1 : 0,
        output,
        Pointer<Int32>.fromAddress(cancelAddress));
    if (status != 0) throw ImagingException(ImagingErrorCode.fromValue(status));
    return FilmPreviewResult(
        image: PreviewImage(
            width: width,
            height: height,
            rgba: Uint8List.fromList(output.asTypedList(pixels.length))),
        recipeFingerprint: fingerprint,
        generation: generation,
        stage: stage);
  });
}
