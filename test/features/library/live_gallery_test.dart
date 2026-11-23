import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/camera/companion/camera_live_manifest.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import 'package:gremote/camera/companion/camera_roll_index.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/camera/http/camera_api.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/features/film_workbench/rolls_page.dart';
import 'package:gremote/features/library/camera_gallery.dart';
import 'package:gremote/features/library/camera_live_photo_page.dart';
import 'package:gremote/features/library/live_gallery_controller.dart';
import 'package:gremote/features/library/live_gallery_page.dart';
import 'package:gremote/media/local/camera_live_media.dart';
import 'package:gremote/platform/device_api.g.dart';

import '../../support/camera_harness.dart';

class _Gallery extends CameraGalleryService {
  _Gallery(int count)
      : files = List.generate(
            count,
            (i) => CameraFile(
                dir: '100RICOH', file: 'R${i.toString().padLeft(7, '0')}.JPG')),
        super(CameraApi(FakeCameraGateways().transport), CameraDeviceHostApi());
  final List<CameraFile> files;
  @override
  Future<List<CameraFile>> photos() async => files;
}

class _LiveApi implements CameraLiveApi {
  int reads = 0, concurrent = 0, maximum = 0;
  Completer<CameraLiveManifest?>? pending;
  bool failFirst = false;
  final Set<int> paired = {1};
  @override
  Future<CameraLiveManifest?> liveManifest(CameraFile photo) async {
    final i = reads++;
    concurrent++;
    if (concurrent > maximum) maximum = concurrent;
    try {
      if (pending != null) return await pending!.future;
      await Future<void>.value();
      if (failFirst && i == 0) throw const FormatException('offline');
      if (!paired.contains(i)) return null;
      return CameraLiveManifest.parse({
        'version': 1,
        'jpeg': {
          'directory': photo.dir,
          'file': photo.file,
          'sha256': 'a' * 64
        },
        'clip': {
          'format': 'mp4',
          'directory': photo.dir,
          'file': '${photo.baseName}.mp4',
          'bytes': 16,
          'sha256': 'b' * 64
        }
      }, photo);
    } finally {
      concurrent--;
    }
  }

  @override
  Future<void> liveClip(CameraLiveManifest manifest,
          Future<void> Function(Uint8List) receive) =>
      throw UnimplementedError();
}

class _Index extends CameraRollIndexController {
  @override
  CameraRollIndexState build() =>
      const CameraRollIndexState(latest: _roll, rolls: [_roll]);
  @override
  Future<void> refresh() async {}
}

const _roll = CameraIndexedRoll(
    id: '11111111111111111111111111111111',
    filmId: 66,
    target: 36,
    journalCount: 0,
    status: CameraRollStatus.closed,
    isLatest: true);

void main() {
  test(
      'camera roll keeps explicit ID fallback when matched catalog has no definition',
      () {
    final catalog = CameraFilmCatalog.fromJson(jsonDecode(
        File('assets/films/camera-profiles/leica-gr3-catalog.json')
            .readAsStringSync()) as Map<String, dynamic>);
    const unknown = CameraIndexedRoll(
        id: '11111111111111111111111111111111', target: 36, filmId: 65535);
    expect(cameraRollName(_roll, catalog: catalog), '5207');
    expect(cameraRollName(unknown, catalog: catalog), '胶卷 65535');
    expect(cameraRollFilm(unknown, catalog), isNull);
    expect(cameraRollName(_roll), '胶卷 66');
  });

  testWidgets(
      'camera roll uses matched camera catalog name and icon in archive and detail',
      (tester) async {
    final catalog = CameraFilmCatalog.fromJson(jsonDecode(
        File('assets/films/camera-profiles/leica-gr3-catalog.json')
            .readAsStringSync()) as Map<String, dynamic>);
    final harness = await CameraHarness.create(overrides: [
      cameraRollIndexProvider.overrideWith(_Index.new),
      cameraFilmCatalogProvider.overrideWith((ref) async => catalog)
    ]);
    addTearDown(harness.dispose);
    await tester.runAsync(harness.connect);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
            theme: GRemoteTheme.dark,
            home: const Scaffold(body: RollsPage()))));
    await tester.pumpAndSettle();
    expect(find.text('5207'), findsOneWidget);
    expect(find.text('胶卷 66'), findsNothing);
    final icon = tester
        .widget<Image>(find.byKey(const ValueKey('camera-roll-film-icon-66')));
    expect((icon.image as AssetImage).assetName,
        'assets/films/camera-icons/66.png');
    await tester.tap(find.byKey(const ValueKey('latest-camera-roll')));
    await tester.pumpAndSettle();
    expect(find.text('5207'), findsOneWidget);
  });

  test('manifest scans are serial, bounded and only actual pairs become Live',
      () async {
    final api = _LiveApi();
    final container = ProviderContainer(overrides: [
      cameraLiveApiProvider.overrideWithValue(api),
      cameraGalleryServiceProvider.overrideWithValue(_Gallery(40))
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(liveGalleryControllerProvider, (_, __) {});
    addTearDown(sub.close);
    await container.read(liveGalleryControllerProvider.notifier).refresh();
    final state = container.read(liveGalleryControllerProvider);
    expect(api.reads, 32);
    expect(api.maximum, 1);
    expect(state.items.length, 1);
    expect(state.hasMore, isTrue);
    await container.read(liveGalleryControllerProvider.notifier).loadMore();
    expect(api.reads, 40);
    expect(container.read(liveGalleryControllerProvider).hasMore, isFalse);
  });
  test('failed manifests stay errors across pages and are not absent clips',
      () async {
    final api = _LiveApi()..failFirst = true;
    final container = ProviderContainer(overrides: [
      cameraLiveApiProvider.overrideWithValue(api),
      cameraGalleryServiceProvider.overrideWithValue(_Gallery(33))
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(liveGalleryControllerProvider, (_, __) {});
    addTearDown(sub.close);
    await container.read(liveGalleryControllerProvider.notifier).refresh();
    expect(container.read(liveGalleryControllerProvider).error,
        contains('1 张配对信息未能读取'));
    await container.read(liveGalleryControllerProvider.notifier).loadMore();
    expect(container.read(liveGalleryControllerProvider).error,
        contains('1 张配对信息未能读取'));
  });
  test('cancel discards pending manifests and preserves cancelled state',
      () async {
    final api = _LiveApi()..pending = Completer<CameraLiveManifest?>();
    final container = ProviderContainer(overrides: [
      cameraLiveApiProvider.overrideWithValue(api),
      cameraGalleryServiceProvider.overrideWithValue(_Gallery(4))
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(liveGalleryControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final task =
        container.read(liveGalleryControllerProvider.notifier).refresh();
    await pumpEventQueue();
    container.read(liveGalleryControllerProvider.notifier).cancel();
    api.pending!.complete(null);
    await task;
    expect(api.reads, 1);
    expect(container.read(liveGalleryControllerProvider).cancelled, isTrue);
    expect(container.read(liveGalleryControllerProvider).loading, isFalse);
  });
  test('saved Live archive requires both files and remains available offline',
      () async {
    final root = await Directory.systemTemp.createTemp('live-archive-test-');
    addTearDown(() => root.delete(recursive: true));
    final archive = LivePhotoArchive(directory: () async => root);
    final staged = await Directory('${root.path}/staged').create();
    final jpeg = await File('${staged.path}/still.jpg').writeAsBytes([1, 2]);
    final mp4 = await File('${staged.path}/motion.mp4').writeAsBytes([3, 4]);
    const photo = CameraFile(dir: '100RICOH', file: 'R0000001.JPG');
    await archive.save(photo, PreparedCameraLivePhoto(staged, jpeg, mp4, 500),
        cameraKey: 'camera-a');
    final saved = await archive.load();
    expect(saved.single.photo, photo);
    expect(saved.single.timestampUs, 500);
    await File(saved.single.mp4Path).delete();
    expect(await archive.load(), isEmpty);
  });
  test(
      'offline archive isolates corrupt records and keeps same filename from different cameras',
      () async {
    final root =
        await Directory.systemTemp.createTemp('live-archive-identity-');
    addTearDown(() => root.delete(recursive: true));
    final archive = LivePhotoArchive(directory: () async => root);
    final staged = await Directory('${root.path}/staged').create();
    final jpeg = await File('${staged.path}/still.jpg').writeAsBytes([1]);
    final mp4 = await File('${staged.path}/motion.mp4').writeAsBytes([2]);
    final pair = PreparedCameraLivePhoto(staged, jpeg, mp4, 0);
    const photo = CameraFile(dir: '100RICOH', file: 'R0000001.JPG');
    await archive.save(photo, pair, cameraKey: 'camera-a');
    await archive.save(photo, pair, cameraKey: 'camera-b');
    final corrupt =
        await Directory('${root.path}/live-photos/corrupt').create();
    await File('${corrupt.path}/pair.json').writeAsString('{broken');
    await File('${corrupt.path}/still.jpg').writeAsBytes([3]);
    await File('${corrupt.path}/motion.mp4').writeAsBytes([4]);
    final saved = await archive.load();
    expect(saved.map((p) => p.cameraKey).toSet(), {'camera-a', 'camera-b'});
    expect(saved.map((p) => p.jpegPath).toSet().length, 2);
    expect(saved.map((p) => p.id).toSet().length, 2);
  });
  test('failed staged archive never overwrites an existing saved pair',
      () async {
    final root = await Directory.systemTemp.createTemp('live-archive-atomic-');
    addTearDown(() => root.delete(recursive: true));
    final archive = LivePhotoArchive(directory: () async => root);
    final staged = await Directory('${root.path}/staged').create();
    final jpeg = await File('${staged.path}/still.jpg').writeAsBytes([1]);
    final mp4 = await File('${staged.path}/motion.mp4').writeAsBytes([2]);
    const photo = CameraFile(dir: '100RICOH', file: 'R0000001.JPG');
    await archive.save(photo, PreparedCameraLivePhoto(staged, jpeg, mp4, 0),
        cameraKey: 'camera-a');
    await expectLater(
        archive.save(
            photo,
            PreparedCameraLivePhoto(
                staged, jpeg, File('${staged.path}/missing.mp4'), 0),
            cameraKey: 'camera-a'),
        throwsA(isA<FileSystemException>()));
    expect((await archive.load()).length, 1);
    final entries = await Directory('${root.path}/live-photos').list().toList();
    expect(entries.where((e) => e.path.contains('.pending-')), isEmpty);
  });
  test(
      'prepared files survive disposal until their native player lease releases',
      () async {
    final root = await Directory.systemTemp.createTemp('live-player-lease-');
    final pair = PreparedCameraLivePhoto(root, File('${root.path}/still.jpg'),
        File('${root.path}/motion.mp4'), 0);
    pair.retain();
    await pair.dispose();
    expect(await root.exists(), isTrue);
    await pair.release();
    expect(await root.exists(), isFalse);
  });
  testWidgets('offline Live has a distinct state and no fabricated Live badge',
      (tester) async {
    final harness = await CameraHarness.create();
    addTearDown(harness.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: harness.container,
        child: ProviderScope(
            overrides: [
              savedLivePhotosProvider.overrideWith((ref) async => []),
              cameraLiveApiProvider.overrideWithValue(null)
            ],
            child: MaterialApp(
                theme: GRemoteTheme.dark,
                home: const Scaffold(body: LiveGalleryPage())))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Live 暂不可用'), findsOneWidget);
    expect(find.text('◎ Live'), findsNothing);
  });
  testWidgets('closed latest roll is visible before any JPEG is downloaded',
      (tester) async {
    final harness = await CameraHarness.create();
    addTearDown(harness.dispose);
    await tester.runAsync(harness.connect);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: harness.container,
        child: ProviderScope(
            overrides: [cameraRollIndexProvider.overrideWith(_Index.new)],
            child: MaterialApp(
                theme: GRemoteTheme.dark,
                home: const Scaffold(body: RollsPage())))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('latest-camera-roll')), findsOneWidget);
    expect(find.text('0 / 36 张 · 已收卷'), findsOneWidget);
    expect(find.widgetWithText(AlbumTag, '相机'), findsOneWidget);
  });
}
