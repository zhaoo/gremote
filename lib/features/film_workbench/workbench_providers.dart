import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../darkroom/darkroom_providers.dart';
import '../../film/catalog/film_catalog.dart';
import '../../film/capture/active_roll_context.dart';
import '../../film/model/film_recipe.dart';
import '../../film/model/film_roll.dart';
import '../../film/preview/film_preview_engine.dart';
import '../../film/store/film_repository.dart';
import '../../imaging/imaging_engine.dart';

final filmCatalogProvider = FutureProvider<FilmCatalog>((ref) async =>
    FilmCatalog.fromJson(
        jsonDecode(await rootBundle.loadString('assets/films/catalog.json'))
            as Map<String, dynamic>));
final filmRepositoryProvider =
    Provider((ref) => FilmRepository(ref.watch(databaseProvider)));
final filmRollRevisionProvider = StateProvider<int>((ref) => 0);
final filmRollsProvider = FutureProvider<List<FilmRoll>>((ref) {
  ref.watch(filmRollRevisionProvider);
  return ref.watch(filmRepositoryProvider).rolls();
});
final rollItemsProvider =
    FutureProvider.autoDispose.family<List<RollItem>, String>((ref, id) {
  ref.watch(filmRollRevisionProvider);
  return ref.watch(filmRepositoryProvider).listItems(id);
});
final selectedFilmRecipeProvider = StateProvider<FilmRecipe?>((ref) => null);
final filmPreviewEngineProvider =
    Provider<FilmPreviewEngine>((ref) => const FfiFilmPreviewEngine());
final trialImageDecoderProvider =
    Provider<TrialImageDecoder>((ref) => const TrialImageDecoder());
final trialSampleLoaderProvider =
    Provider<Future<PreviewImage> Function()>((ref) {
  final decoder = ref.watch(trialImageDecoderProvider);
  return () async {
    final bytes =
        await rootBundle.load('assets/images/film_workbench_sample.jpg');
    return decoder.decode(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  };
});

/// Decode before entering the native renderer. Both dimensions are bounded.
class TrialImageDecoder {
  const TrialImageDecoder();
  Future<PreviewImage> decode(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('请选择 20 MB 以内的 JPEG');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale =
          math.min(1.0, 960 / math.max(descriptor.width, descriptor.height));
      codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).round()),
          targetHeight: math.max(1, (descriptor.height * scale).round()));
      image = (await codec.getNextFrame()).image;
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null) throw const FormatException('无法读取照片');
      return PreviewImage(
          width: image.width,
          height: image.height,
          rgba: pixels.buffer
              .asUint8List(pixels.offsetInBytes, pixels.lengthInBytes));
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}

// Hydrated at app startup as well as after roll transactions. Stale asynchronous
// reads cannot restore a roll that was closed in a newer generation.
final activeRollHydrationProvider = FutureProvider<void>((ref) async {
  ref.watch(filmRollRevisionProvider);
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final repository = ref.read(filmRepositoryProvider);
  final roll = await repository.activeRoll();
  final recipe =
      roll == null ? null : await repository.recipe(roll.recipeFingerprint);
  if (disposed) return;
  ref.read(activeRollCaptureContextProvider.notifier).state = roll == null
      ? null
      : FrozenRollContext(
          rollId: roll.id, recipeJson: jsonEncode(recipe!.toJson()));
});
