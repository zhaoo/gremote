import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../camera/companion/camera_live_manifest.dart';
import '../../camera/http/camera_files.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../film_workbench/companion_providers.dart';
import '../../media/local/camera_live_media.dart';
import 'camera_gallery.dart';
import 'camera_live_photo_page.dart';

/// A verified manifest is the only camera-side source of Live membership.
/// Null means no paired clip; request errors remain visible and retryable.
class LiveGalleryItem {
  const LiveGalleryItem(this.photo, {this.manifest, this.saved});
  final CameraFile photo;
  final CameraLiveManifest? manifest;
  final SavedLivePhoto? saved;
  String get id => photo.remoteId;
}

class LiveGalleryState {
  const LiveGalleryState(
      {this.items = const [],
      this.loading = false,
      this.hasMore = false,
      this.cancelled = false,
      this.checked = 0,
      this.error});
  final List<LiveGalleryItem> items;
  final bool loading, hasMore, cancelled;
  final int checked;
  final String? error;
}

class SavedLivePhoto {
  const SavedLivePhoto(
      this.photo, this.jpegPath, this.mp4Path, this.timestampUs,
      {this.cameraKey, this.savedAt = 0});
  final CameraFile photo;
  final String jpegPath, mp4Path;
  final int? timestampUs;
  final String? cameraKey;
  final int savedAt;
  String get id => '${cameraKey ?? 'legacy:$jpegPath'}:${photo.remoteId}';
}

/// App copies are immutable generations. A complete staged directory is renamed
/// into place only after both files and the record have been written.
class LivePhotoArchive {
  const LivePhotoArchive({this.directory = getApplicationSupportDirectory});
  final Future<Directory> Function() directory;
  Future<Directory> _root() async =>
      Directory('${(await directory()).path}/live-photos')
          .create(recursive: true);
  Future<List<SavedLivePhoto>> load() async {
    final root = await _root();
    final result = <String, SavedLivePhoto>{};
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory ||
          entry.path.split(Platform.pathSeparator).last.startsWith('.')) {
        continue;
      }
      try {
        final record = File('${entry.path}/pair.json'),
            jpeg = File('${entry.path}/still.jpg'),
            mp4 = File('${entry.path}/motion.mp4');
        if (await FileSystemEntity.type(record.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await FileSystemEntity.type(jpeg.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await FileSystemEntity.type(mp4.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await record.length() > 8192 ||
            await jpeg.length() == 0 ||
            await jpeg.length() > 100000000 ||
            await mp4.length() == 0 ||
            await mp4.length() > 100000000) {
          continue;
        }
        final json = jsonDecode(await record.readAsString());
        if (json is! Map ||
            json['dir'] is! String ||
            json['file'] is! String ||
            (json['cameraKey'] != null &&
                (json['cameraKey'] is! String ||
                    (json['cameraKey'] as String).isEmpty ||
                    (json['cameraKey'] as String).length > 256)) ||
            (json['timestamp'] != null &&
                (json['timestamp'] is! int ||
                    (json['timestamp'] as int) < 0)) ||
            (json['savedAt'] != null && json['savedAt'] is! int)) {
          continue;
        }
        final photo = CameraFile(
            dir: json['dir'] as String, file: json['file'] as String);
        CameraLiveManifest.pathFor(photo);
        final saved = SavedLivePhoto(
            photo, jpeg.path, mp4.path, json['timestamp'] as int?,
            cameraKey: json['cameraKey'] as String?,
            savedAt: json['savedAt'] as int? ?? 0);
        if ((result[saved.id]?.savedAt ?? -1) <= saved.savedAt) {
          result[saved.id] = saved;
        }
      } on FileSystemException catch (_) {
        /* One unavailable pair does not hide the archive. */
      } on FormatException catch (_) {/* Keep other complete pairs visible. */}
    }
    return result.values.toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  }

  Future<void> save(CameraFile photo, PreparedCameraLivePhoto pair,
      {required String cameraKey}) async {
    if (cameraKey.isEmpty || cameraKey.length > 256) {
      throw const FormatException('相机身份尚未读取，请重新连接后保存离线副本');
    }
    CameraLiveManifest.pathFor(photo);
    final root = await _root();
    final staged = await root.createTemp('.pending-');
    try {
      final jpeg = await pair.jpeg.copy('${staged.path}/still.jpg');
      final mp4 = await pair.mp4.copy('${staged.path}/motion.mp4');
      if (await jpeg.length() == 0 || await mp4.length() == 0) {
        throw const FormatException('离线 Live 文件为空');
      }
      final jpegHash = (await sha256.bind(jpeg.openRead()).first).toString();
      final mp4Hash = (await sha256.bind(mp4.openRead()).first).toString();
      final key = sha256
          .convert(
              utf8.encode('$cameraKey:${photo.remoteId}:$jpegHash:$mp4Hash'))
          .toString();
      await File('${staged.path}/pair.json').writeAsString(
          jsonEncode({
            'version': 2,
            'cameraKey': cameraKey,
            'dir': photo.dir,
            'file': photo.file,
            'timestamp': pair.presentationTimestampUs,
            'savedAt': DateTime.now().microsecondsSinceEpoch
          }),
          flush: true);
      final suffix = staged.path
          .split(Platform.pathSeparator)
          .last
          .substring('.pending-'.length);
      final target = Directory('${root.path}/$key-$suffix');
      await staged.rename(target.path);
    } finally {
      if (await staged.exists()) await staged.delete(recursive: true);
    }
  }
}

final liveCameraArchiveKeyProvider = Provider<String?>((ref) {
  final connection = ref.watch(connectionControllerProvider);
  return connection is ConnectionReady
      ? connection.cameraKey ??
          ref.watch(effectiveCompanionIdentityProvider)?.instanceId
      : null;
});

final livePhotoArchiveProvider =
    Provider<LivePhotoArchive>((ref) => const LivePhotoArchive());
final savedLivePhotosProvider = FutureProvider<List<SavedLivePhoto>>(
    (ref) => ref.watch(livePhotoArchiveProvider).load());
final liveGalleryControllerProvider =
    NotifierProvider.autoDispose<LiveGalleryController, LiveGalleryState>(
        LiveGalleryController.new,
        dependencies: [cameraLiveApiProvider, cameraGalleryServiceProvider]);

class LiveGalleryController extends AutoDisposeNotifier<LiveGalleryState> {
  int _generation = 0, _offset = 0;
  List<CameraFile> _photos = const [];
  bool _disposed = false;
  final _failures = <String, String>{};
  static const pageSize = 32;
  @override
  LiveGalleryState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
    });
    ref.listen(cameraLiveApiProvider, (previous, next) {
      if (!identical(previous, next)) {
        cancel();
        state = const LiveGalleryState();
        if (next != null) unawaited(refresh());
      }
    });
    return const LiveGalleryState();
  }

  void cancel() {
    _generation++;
    if (!_disposed) {
      state = LiveGalleryState(
          items: state.items,
          checked: state.checked,
          hasMore: state.hasMore,
          cancelled: true,
          error: state.error);
    }
  }

  Future<void> refresh() async {
    if (state.loading) return;
    final api = ref.read(cameraLiveApiProvider);
    if (api == null) return;
    final generation = ++_generation;
    state = LiveGalleryState(items: state.items, loading: true);
    try {
      final photos = (await ref.read(cameraGalleryServiceProvider).photos())
          .where((f) => f.extension != 'DNG')
          .toList();
      if (_disposed || generation != _generation) return;
      _photos = photos;
      _offset = 0;
      _failures.clear();
      state = const LiveGalleryState(loading: true);
      await _scan(api, generation);
    } catch (error) {
      if (!_disposed && generation == _generation) {
        state = LiveGalleryState(
            items: state.items,
            error: '读取 Live 失败：$error',
            checked: state.checked,
            hasMore: true);
      }
    }
  }

  Future<void> loadMore() async {
    final api = ref.read(cameraLiveApiProvider);
    if (state.loading || api == null || !state.hasMore) return;
    final generation = ++_generation;
    state = LiveGalleryState(
        items: state.items,
        checked: state.checked,
        loading: true,
        hasMore: true);
    await _scan(api, generation);
  }

  Future<void> _scan(CameraLiveApi api, int generation) async {
    final items = [...state.items];
    var checked = state.checked;
    final end = (_offset + pageSize).clamp(0, _photos.length);
    // Manifest requests are serial and bounded; no photo/video is downloaded.
    while (_offset < end) {
      if (_disposed ||
          generation != _generation ||
          !identical(ref.read(cameraLiveApiProvider), api)) {
        return;
      }
      final photo = _photos[_offset];
      try {
        final manifest = await ref
            .read(cameraGalleryServiceProvider)
            .transferGate
            .thumbnail(() => api.liveManifest(photo));
        if (_disposed || generation != _generation) return;
        if (manifest != null) {
          items.add(LiveGalleryItem(photo, manifest: manifest));
        }
      } catch (error) {
        _failures[photo.remoteId] = '${photo.file}：$error';
      }
      if (_disposed || generation != _generation) return;
      _offset++;
      checked++;
      state = LiveGalleryState(
          items: List.unmodifiable(items),
          checked: checked,
          loading: true,
          hasMore: _offset < _photos.length);
    }
    if (_disposed || generation != _generation) return;
    state = LiveGalleryState(
        items: List.unmodifiable(items),
        checked: checked,
        hasMore: _offset < _photos.length,
        error: _failures.isEmpty
            ? null
            : '${_failures.length} 张配对信息未能读取，请重新读取。${_failures.values.first}');
  }
}
