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
  const HomeCoverData(
      {required this.settings,
      required this.available,
      required this.frames,
      this.configError = false});
  final HomeCoverSettings settings;
  final List<LocalMediaItem> available;
  final List<CoverFrame> frames;
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
  final recent = (await repository.recentAlbumImports())
      .where((e) => uris[e.id] == e.uri)
      .toList();
  final chosen = resolveCoverItems(
      settings, settings.entries.isEmpty ? recent : available);
  final frames = <CoverFrame>[];
  for (final item in chosen) {
    if (!active) break;
    try {
      final bytes = await gateway.thumbnail(item.id, 1024);
      if (bytes == null || !active) continue;
      // Reject corrupt thumbnails before replacing the previous visible frame.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1024);
      try {
        final decoded = await codec.getNextFrame();
        decoded.image.dispose();
      } finally {
        codec.dispose();
      }
      final entry = settings.entries
              .where((e) => e.id == item.id && e.uri == item.uri)
              .firstOrNull ??
          HomeCoverEntry(id: item.id, uri: item.uri);
      frames.add(CoverFrame(entry: entry, bytes: bytes));
    } catch (_) {
      /* Missing or unreadable media is omitted, never persisted away. */
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
      configError: configError);
});
