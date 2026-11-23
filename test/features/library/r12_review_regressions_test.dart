import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/camera/companion/camera_live_manifest.dart';
import 'package:gremote/camera/companion/camera_roll_index.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/camera/http/camera_api.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/features/film_workbench/camera_roll_detail_page.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import 'package:gremote/features/library/camera_gallery.dart';
import 'package:gremote/features/library/camera_live_photo_page.dart';
import 'package:gremote/features/library/live_gallery_controller.dart';
import 'package:gremote/media/local/camera_live_media.dart';
import 'package:gremote/platform/device_api.g.dart';
import 'package:gremote/platform/motion_photo_api.dart';

import '../../support/camera_harness.dart';

const _photo = CameraFile(dir: '100RICOH', file: 'R0000001.JPG');
const _roll = CameraIndexedRoll(
    id: '11111111111111111111111111111111',
    filmId: 66,
    target: 36,
    journalCount: 1,
    status: CameraRollStatus.closed,
    isLatest: true,
    photos: [
      CameraIndexedPhoto(
          file: _photo,
          rollId: '11111111111111111111111111111111',
          frame: 1,
          target: 36)
    ]);

class _Index extends CameraRollIndexController {
  _Index({this.truncated = false, this.skipped = 0, this.fail = false});
  final bool truncated, fail;
  final int skipped;
  int refreshes = 0;
  @override
  CameraRollIndexState build() => CameraRollIndexState(
      latest: _roll,
      rolls: [_roll],
      truncated: truncated,
      skipped: skipped,
      checked: 4096,
      hasMore: fail);
  @override
  Future<void> loadMore() async {
    if (fail) throw const FormatException('测试索引读取失败');
  }

  @override
  Future<void> refresh() async {
    refreshes++;
  }
}

class _Gallery extends CameraGalleryService {
  _Gallery()
      : super(CameraApi(FakeCameraGateways().transport), CameraDeviceHostApi());
  int downloads = 0;
  @override
  Future<Uint8List> thumbnail(CameraFile file,
          {bool Function()? isCurrent}) async =>
      throw StateError('no fixture thumbnail');
  @override
  Future<String> download(CameraFile file, {bool Function()? isCurrent}) async {
    downloads++;
    throw StateError('fixture prevents native save');
  }
}

class _Api implements CameraLiveApi {
  @override
  Future<CameraLiveManifest?> liveManifest(CameraFile file) async => null;
  @override
  Future<void> liveClip(CameraLiveManifest manifest,
          Future<void> Function(Uint8List) receive) =>
      throw UnimplementedError();
}

class _Native extends MotionPhotoApi {
  int exports = 0;
  @override
  Future<String> export(String jpeg, String mp4, String name,
      {int? presentationTimestampUs}) async {
    exports++;
    return 'content://motion/1';
  }

  @override
  Future<MotionVideoPlayer> openPlayer(String path) async =>
      const MotionVideoPlayer(42, 192, 128, 3000);
  @override
  Future<MotionVideoInfo> inspectVideo(String path) async =>
      const MotionVideoInfo(3000, []);
  @override
  Future<Map<String, Object?>> playerControl(int id, String action,
          {int? positionMs}) async =>
      {};
}

class _Media extends CameraLiveMedia {
  _Media(this.pair, _Native native, {this.failFirst = false})
      : super(native: native);
  final PreparedCameraLivePhoto pair;
  final bool failFirst;
  int attempts = 0;
  @override
  Future<PreparedCameraLivePhoto?> prepare(CameraLiveApi api, CameraFile photo,
      {required bool Function() isCurrent, String? sourceCameraKey}) async {
    if (failFirst && attempts++ == 0) throw const FormatException('相机已断开');
    return PreparedCameraLivePhoto(
        pair.directory, pair.jpeg, pair.mp4, pair.presentationTimestampUs,
        sourceCameraKey: sourceCameraKey);
  }
}

class _Archive extends LivePhotoArchive {
  _Archive({this.failures = 0});
  int failures;
  final keys = <String>[];
  @override
  Future<void> save(CameraFile photo, PreparedCameraLivePhoto pair,
      {required String cameraKey}) async {
    keys.add(cameraKey);
    if (failures-- > 0) throw const FileSystemException('disk full');
  }

  @override
  Future<List<SavedLivePhoto>> load() async => [];
}

final _identity = StateProvider<String>((ref) => 'camera-a');
final _api = StateProvider<CameraLiveApi>((ref) => _Api());

void main() {
  for (final mode in ['truncated', 'skipped', 'loadFailure']) {
    testWidgets('whole roll refuses $mode and displays an inline retry',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final index = _Index(
          truncated: mode == 'truncated',
          skipped: mode == 'skipped' ? 1 : 0,
          fail: mode == 'loadFailure');
      final gallery = _Gallery();
      final harness = await CameraHarness.create(overrides: [
        cameraRollIndexProvider.overrideWith(() => index),
        cameraGalleryServiceProvider.overrideWithValue(gallery)
      ]);
      addTearDown(harness.dispose);
      await tester.runAsync(harness.connect);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
              theme: GRemoteTheme.dark,
              home: const CameraRollDetailPage(_roll))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存整卷'));
      await tester.tap(find.text('保存整卷'));
      await tester.pumpAndSettle();
      expect(gallery.downloads, 0);
      expect(find.byType(CameraGallery), findsOneWidget);
      expect(
          tester
              .widget<CameraGallery>(find.byType(CameraGallery))
              .startDownload,
          isFalse);
      expect(
          find.text(mode == 'loadFailure'
              ? '测试索引读取失败'
              : mode == 'truncated'
                  ? '相机照片超过单次读取上限（4096 张），无法确认整卷完整。请改用相机照片按张保存。'
                  : '部分照片卷标记未能读取，无法确认整卷完整。请重新读取后重试。'),
          findsOneWidget);
      await tester.ensureVisible(find.text('重新读取胶卷'));
      await tester.tap(find.text('重新读取胶卷'));
      await tester.pump();
      expect(index.refreshes, 1);
    });
  }
  Future<({CameraHarness harness, _Native native, _Archive archive})> pumpLive(
      WidgetTester tester,
      {required bool failPrepare,
      int archiveFailures = 0}) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final root = Directory.systemTemp.createTempSync('r12-review-live-');
    addTearDown(() async {
      try {
        await root.delete(recursive: true);
      } on FileSystemException {
        if (root.existsSync()) rethrow;
      }
    });
    final pair = PreparedCameraLivePhoto(
        root,
        File('${root.path}/still.jpg')
          ..writeAsBytesSync(
              File('assets/images/street_moment.jpg').readAsBytesSync()),
        File('${root.path}/motion.mp4')..writeAsBytesSync([1]),
        0);
    final native = _Native(), archive = _Archive(failures: archiveFailures);
    final harness = await CameraHarness.create(overrides: [
      cameraGalleryServiceProvider.overrideWithValue(_Gallery()),
      cameraLiveApiProvider.overrideWith((ref) => ref.watch(_api)),
      liveCameraArchiveKeyProvider.overrideWith((ref) => ref.watch(_identity)),
      companionHotspotPairingProvider.overrideWith((ref) async => null),
      companionIdentityHydrationProvider.overrideWith((ref) async {}),
      cameraLiveMediaProvider
          .overrideWithValue(_Media(pair, native, failFirst: failPrepare)),
      livePhotoArchiveProvider.overrideWithValue(archive)
    ]);
    addTearDown(harness.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
            theme: GRemoteTheme.dark,
            home: const CameraLivePhotoPage(_photo))));
    await tester.pumpAndSettle();
    return (harness: harness, native: native, archive: archive);
  }

  testWidgets('unavailable Live preview performs no export or archive writes',
      (tester) async {
    final env = await pumpLive(tester, failPrepare: false);
    expect(find.textContaining('Live 暂不可用'), findsOneWidget);
    expect(env.native.exports, 0);
    expect(env.archive.keys, isEmpty);
  });

  testWidgets(
      'retry on camera B binds the prepared pair to B instead of page creation camera A',
      (tester) async {
    final env = await pumpLive(tester, failPrepare: true);
    expect(find.text('无法读取 Live'), findsOneWidget);
    env.harness.container.read(_identity.notifier).state = 'camera-b';
    env.harness.container.read(_api.notifier).state = _Api();
    await tester.tap(find.text('重新读取'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存 Live'));
    await tester.tap(find.text('保存 Live'));
    await tester.pumpAndSettle();
    expect(env.archive.keys, ['camera-b']);
  }, skip: true); // Live 暂不可用，保留重新开放后的回归
  testWidgets(
      'archive-only retry after offline-copy failure does not export a duplicate system Live',
      (tester) async {
    final env = await pumpLive(tester, failPrepare: false, archiveFailures: 1);
    await tester.ensureVisible(find.text('保存 Live'));
    await tester.tap(find.text('保存 Live'));
    await tester.pumpAndSettle();
    expect(env.native.exports, 1);
    expect(find.text('重试离线保存'), findsOneWidget);
    await tester.tap(find.text('重试离线保存'));
    await tester.pumpAndSettle();
    expect(env.native.exports, 1);
    expect(env.archive.keys, ['camera-a', 'camera-a']);
    expect(find.text('已保存 Live'), findsOneWidget);
  }, skip: true); // Live 暂不可用，保留重新开放后的回归
}
