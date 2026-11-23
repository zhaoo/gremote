import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/film_workbench/companion_providers.dart';
import '../../features/library/camera_gallery.dart';
import '../http/camera_files.dart';
import 'companion_client.dart';

enum CameraRollStatus { active, paused, closed }

class CameraIndexedPhoto {
  const CameraIndexedPhoto(
      {required this.file,
      required this.rollId,
      required this.frame,
      required this.target,
      this.filmCode});
  final CameraFile file;
  final String rollId;
  final int frame, target;
  final int? filmCode;

  factory CameraIndexedPhoto.parse(Object? wire) {
    if (wire is! Map ||
        !_id(wire['id']) ||
        !_integer(wire['target'], 1, 64) ||
        !_integer(wire['frame'], 1, wire['target'] as int) ||
        wire['directory'] is! String ||
        !_full(RegExp(r'^[1-9][0-9]{2}[A-Za-z0-9_]{5}$'),
            wire['directory'] as String) ||
        wire['file'] is! String ||
        !_full(RegExp(r'^[A-Za-z0-9_]{8}\.(?:[Jj][Pp][Gg]|[Dd][Nn][Gg])$'),
            wire['file'] as String) ||
        !_integer(wire['filmCode'], 0, 65535)) {
      throw const FormatException('相机胶卷照片索引无效');
    }
    return CameraIndexedPhoto(
        file: CameraFile(
            dir: wire['directory'] as String, file: wire['file'] as String),
        rollId: wire['id'] as String,
        frame: wire['frame'] as int,
        target: wire['target'] as int,
        filmCode: wire['filmCode'] == 0 ? null : wire['filmCode'] as int);
  }
}

class CameraIndexedRoll {
  const CameraIndexedRoll(
      {required this.id,
      required this.target,
      this.filmId,
      this.journalCount,
      this.status,
      this.isLatest = false,
      this.photos = const []});
  final String id;
  final int target;
  final int? filmId, journalCount;
  final CameraRollStatus? status;
  final bool isLatest;
  final List<CameraIndexedPhoto> photos;
  int get verifiedPhotoCount => photos.map((p) => p.frame).toSet().length;

  factory CameraIndexedRoll.parseLatest(Object? wire) {
    if (wire is! Map ||
        !_id(wire['id']) ||
        !_integer(wire['sequence'], 1, 0xffffffff) ||
        !_integer(wire['target'], 1, 64) ||
        !_integer(wire['count'], 0, wire['target'] as int) ||
        !_integer(wire['filmId'], 1, 65535) ||
        !_integer(wire['status'], 1, 3)) {
      throw const FormatException('相机最新胶卷记录无效');
    }
    return CameraIndexedRoll(
        id: wire['id'] as String,
        target: wire['target'] as int,
        filmId: wire['filmId'] as int,
        journalCount: wire['count'] as int,
        status: CameraRollStatus.values[(wire['status'] as int) - 1],
        isLatest: true);
  }

  CameraIndexedRoll withPhotos(List<CameraIndexedPhoto> value) =>
      CameraIndexedRoll(
          id: id,
          target: target,
          filmId: filmId,
          journalCount: journalCount,
          status: status,
          isLatest: isLatest,
          photos: List.unmodifiable(value));
}

bool _full(RegExp expression, String value) =>
    expression.firstMatch(value)?.end == value.length;
bool _integer(Object? value, int min, int max) =>
    value is int && value >= min && value <= max;
bool _id(Object? value) =>
    value is String &&
    _full(RegExp(r'^[a-f0-9]{32}$'), value) &&
    value != '0' * 32;

class CameraRollIndexPage {
  const CameraRollIndexPage(this.photos, this.nextCursor, this.hasMore,
      this.truncated, this.checked, this.skipped);
  final List<CameraIndexedPhoto> photos;
  final int nextCursor, checked, skipped;
  final bool hasMore, truncated;
  factory CameraRollIndexPage.parse(Map<String, dynamic> wire, int cursor) {
    if (wire['version'] != 1 ||
        wire['photos'] is! List ||
        (wire['photos'] as List).length > 12 ||
        wire['hasMore'] is! bool ||
        wire['truncated'] is! bool ||
        !_integer(wire['nextCursor'], 0, 0xffffffff) ||
        !_integer(wire['checked'], 0, 4096) ||
        !_integer(wire['skipped'], 0, 0xffffffff) ||
        (wire['hasMore'] == true &&
            ((wire['nextCursor'] as int) <= cursor ||
                wire['truncated'] == true)) ||
        (wire['hasMore'] == false && wire['nextCursor'] != 0)) {
      throw const FormatException('相机胶卷分页信息无效');
    }
    return CameraRollIndexPage(
        List.unmodifiable(
            (wire['photos'] as List).map(CameraIndexedPhoto.parse)),
        wire['nextCursor'] as int,
        wire['hasMore'] as bool,
        wire['truncated'] as bool,
        wire['checked'] as int,
        wire['skipped'] as int);
  }
}

abstract interface class CameraRollIndexApi {
  Future<CameraIndexedRoll?> latest();
  Future<CameraRollIndexPage> photos(int cursor);
}

class CompanionCameraRollIndexApi implements CameraRollIndexApi {
  CompanionCameraRollIndexApi(this.client);
  final CompanionClient client;
  @override
  Future<CameraIndexedRoll?> latest() async {
    final wire = await client.readRollIndex('latest');
    if (wire['version'] != 1 || !wire.containsKey('latest')) {
      throw const FormatException('相机胶卷服务版本无效');
    }
    return wire['latest'] == null
        ? null
        : CameraIndexedRoll.parseLatest(wire['latest']);
  }

  @override
  Future<CameraRollIndexPage> photos(int cursor) async =>
      CameraRollIndexPage.parse(
          await client.readRollIndex('photos/$cursor'), cursor);
}

final cameraRollIndexApiProvider = Provider<CameraRollIndexApi?>((ref) {
  if (!ref.watch(companionNetworkReadyProvider)) return null;
  final api = ref.watch(companionSyncControllerProvider)?.api;
  return api is CompanionClient ? CompanionCameraRollIndexApi(api) : null;
});

class CameraRollIndexState {
  const CameraRollIndexState(
      {this.latest,
      this.rolls = const [],
      this.loading = false,
      this.scanning = false,
      this.hasMore = false,
      this.truncated = false,
      this.checked = 0,
      this.skipped = 0,
      this.error});
  final CameraIndexedRoll? latest;
  final List<CameraIndexedRoll> rolls;
  final bool loading, scanning, hasMore, truncated;
  final int checked, skipped;
  final String? error;
}

final cameraRollIndexProvider = NotifierProvider.autoDispose<
    CameraRollIndexController,
    CameraRollIndexState>(CameraRollIndexController.new);

class CameraRollIndexController
    extends AutoDisposeNotifier<CameraRollIndexState> {
  int _session = 0, _cursor = 0;
  @override
  CameraRollIndexState build() {
    ref.watch(cameraRollIndexApiProvider);
    _session++;
    _cursor = 0;
    ref.onDispose(() => _session++);
    return const CameraRollIndexState();
  }

  void cancel() {
    _session++;
    state = CameraRollIndexState(
        latest: state.latest,
        rolls: state.rolls,
        hasMore: state.hasMore,
        truncated: state.truncated,
        checked: state.checked,
        skipped: state.skipped);
  }

  Future<void> refresh() async {
    final api = ref.read(cameraRollIndexApiProvider);
    final session = ++_session;
    _cursor = 0;
    if (api == null) {
      state = const CameraRollIndexState(error: '正在连接相机服务，请稍后重新读取');
      return;
    }
    state = const CameraRollIndexState(loading: true);
    try {
      final latest = await ref
          .read(cameraGalleryServiceProvider)
          .transferGate
          .thumbnail(() {
        if (session != _session) throw StateError('Camera session changed');
        return api.latest();
      });
      if (session != _session) return;
      // Publish the journal immediately, including a closed roll with no JPEGs.
      state = CameraRollIndexState(
          latest: latest,
          rolls: latest == null ? const [] : [latest],
          hasMore: true);
      await loadMore();
      // FAT enumeration starts with older originals. Continue in bounded,
      // cancellable turns until the known latest roll's saved frames are found.
      // Journal state remains visible throughout and original transfer pauses us.
      for (var pages = 1; pages < 256 && session == _session; pages++) {
        final current = state.latest;
        if (!state.hasMore ||
            state.error != null ||
            current == null ||
            current.verifiedPhotoCount >= (current.journalCount ?? 0)) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (session != _session) break;
        await loadMore();
      }
    } catch (_) {
      if (session == _session) {
        state = const CameraRollIndexState(error: '读取相机胶卷失败，请检查连接后重试');
      }
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.scanning || !state.hasMore) return;
    final api = ref.read(cameraRollIndexApiProvider);
    if (api == null) return;
    final session = _session;
    final before = state;
    state = CameraRollIndexState(
        latest: before.latest,
        rolls: before.rolls,
        scanning: true,
        hasMore: true,
        checked: before.checked,
        skipped: before.skipped);
    try {
      final page = await ref
          .read(cameraGalleryServiceProvider)
          .transferGate
          .thumbnail(() {
        if (session != _session) throw StateError('Camera session changed');
        return api.photos(_cursor);
      });
      if (session != _session) return;
      if (page.checked < before.checked) {
        throw const FormatException('相机胶卷扫描已变化');
      }
      final rolls = mergeCameraRollPhotos(before.rolls, page.photos);
      _cursor = page.nextCursor;
      state = CameraRollIndexState(
          latest: rolls.where((r) => r.isLatest).firstOrNull,
          rolls: rolls,
          hasMore: page.hasMore,
          truncated: page.truncated,
          checked: page.checked,
          skipped: page.skipped);
    } catch (_) {
      if (session == _session) {
        state = CameraRollIndexState(
            latest: before.latest,
            rolls: before.rolls,
            hasMore: before.hasMore,
            checked: before.checked,
            skipped: before.skipped,
            error: '部分相机胶卷尚未读取，请刷新重试');
      }
    }
  }
}

/// Markers prove roll membership and saved frames, not historical roll closure.
List<CameraIndexedRoll> mergeCameraRollPhotos(
    List<CameraIndexedRoll> existing, List<CameraIndexedPhoto> photos) {
  final grouped = {for (final roll in existing) roll.id: roll};
  for (final photo in photos) {
    var roll = grouped[photo.rollId];
    if (roll != null && roll.target != photo.target) {
      throw const FormatException('胶卷张数记录不一致');
    }
    final code = photo.filmCode;
    final film = code == null
        ? null
        : code >= 0x1001 && code <= 0x104e
            ? code - 0x1000
            : code >= 0x1121 && code <= 0x114e
                ? code - 0x1100
                : null;
    roll ??=
        CameraIndexedRoll(id: photo.rollId, target: photo.target, filmId: film);
    // Keep every independently tagged original. The gallery groups JPEG/RAW
    // siblings by their real path; a marker never implies an unverified sibling.
    final originals = <String, CameraIndexedPhoto>{
      for (final candidate in [...roll.photos, photo])
        candidate.file.remoteId: candidate,
    };
    final entries = originals.values.toList()
      ..sort((a, b) {
        final frame = a.frame.compareTo(b.frame);
        if (frame != 0) return frame;
        final format = (a.file.extension == 'DNG' ? 1 : 0)
            .compareTo(b.file.extension == 'DNG' ? 1 : 0);
        return format != 0
            ? format
            : a.file.remoteId.compareTo(b.file.remoteId);
      });
    grouped[photo.rollId] = roll.withPhotos(entries);
  }
  return List.unmodifiable(grouped.values);
}
