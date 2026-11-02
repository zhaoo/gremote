import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../darkroom/darkroom_providers.dart';
import '../../media/local/local_media_repository.dart';
import '../../media/local/media_gateway.dart';
import '../library/library_controller.dart';
import 'home_cover_settings.dart';
import 'home_cover_repository.dart';

class CoverFrame {
  const CoverFrame({required this.entry, required this.bytes});
  final HomeCoverEntry entry;
  final Uint8List bytes;
}

class HomeCoverData {
  HomeCoverData(
      {required this.settings,
      required this.available,
      required this.frames,
      List<CoverFrame>? recentFrames,
      this.configError = false})
      : recentFrames = recentFrames ?? frames;
  final HomeCoverSettings settings;
  final List<LocalMediaItem> available;
  final List<CoverFrame> frames, recentFrames;
  final bool configError;
}

final homeCoverRevisionProvider = StateProvider<int>((ref) => 0);
final homeCoverRepositoryProvider =
    Provider((ref) => HomeCoverRepository(ref.watch(databaseProvider)));
final homeCoverDataProvider =
    FutureProvider.autoDispose<HomeCoverData>((ref) async {
  ref.watch(homeCoverRevisionProvider);
  ref.watch(libraryControllerProvider.select((s) => s.items));
  var active = true;
  ref.onDispose(() => active = false);
  final repository = ref.watch(localMediaRepositoryProvider),
      gateway = ref.watch(mediaGatewayProvider);
  HomeCoverSettings settings;
  var configError = false;
  try {
    settings = await ref.watch(homeCoverRepositoryProvider).load();
  } on FormatException {
    settings = const HomeCoverSettings(useDefault: true);
    configError = true;
  }
  if (await gateway.access() == MediaAccess.denied) {
    return HomeCoverData(
        settings: settings,
        available: [],
        frames: [],
        configError: configError);
  }
  final live = await gateway.queryImages();
  final uris = {for (final e in live) e.id: e.uri};
  final available =
      (await repository.album()).where((e) => uris[e.id] == e.uri).toList();
  Future<CoverFrame?> read(LocalMediaItem item) async {
    if (!active || uris[item.id] != item.uri) return null;
    try {
      final bytes = await gateway.thumbnail(item.id, 1024);
      if (bytes == null || !active) return null;
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1024);
      try {
        final decoded = await codec.getNextFrame();
        decoded.image.dispose();
      } finally {
        codec.dispose();
      }
      return CoverFrame(
          entry: HomeCoverEntry(id: item.id, uri: item.uri), bytes: bytes);
    } catch (_) {
      return null;
    }
  }

  // Read in import order until five readable works have been collected.
  final recentFrames = <CoverFrame>[];
  var offset = 0;
  while (active && recentFrames.length < 5) {
    final batch = await repository.recentAlbumImports(offset: offset);
    for (final item in batch) {
      final frame = await read(item);
      if (frame != null) recentFrames.add(frame);
      if (recentFrames.length == 5 || !active) break;
    }
    if (batch.length < 5) break;
    offset += batch.length;
  }
  final frames = <CoverFrame>[];
  if (!settings.useDefault) {
    if (settings.entries.isEmpty) {
      frames.addAll(recentFrames);
    } else {
      for (final item in resolveCoverItems(settings, available)) {
        final recent = recentFrames
            .where((f) => f.entry.id == item.id && f.entry.uri == item.uri)
            .firstOrNull;
        final frame = recent ?? await read(item);
        if (frame != null) {
          final entry = settings.entries
              .firstWhere((e) => e.id == item.id && e.uri == item.uri);
          frames.add(CoverFrame(entry: entry, bytes: frame.bytes));
        }
      }
    }
  }
  if (await gateway.access() == MediaAccess.denied) {
    return HomeCoverData(
        settings: settings,
        available: [],
        frames: [],
        configError: configError);
  }
  return HomeCoverData(
      settings: settings,
      available: available,
      frames: frames,
      recentFrames: recentFrames,
      configError: configError);
});
