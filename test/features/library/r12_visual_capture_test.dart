import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/app/router.dart';
import 'package:go_router/go_router.dart';
import 'package:gremote/camera/companion/camera_live_manifest.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/camera/companion/camera_roll_index.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/features/film_workbench/camera_roll_detail_page.dart';
import 'package:gremote/features/film_workbench/roll_detail_page.dart';
import 'package:gremote/features/film_workbench/workbench_providers.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/features/home/home_page.dart';
import 'package:gremote/features/home/import_history.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import 'package:gremote/features/library/camera_gallery.dart';
import 'package:gremote/features/library/camera_live_photo_page.dart';
import 'package:gremote/features/library/library_page.dart';
import 'package:gremote/features/library/live_gallery_controller.dart';
import 'package:gremote/media/local/camera_live_media.dart';
import 'package:gremote/platform/motion_photo_api.dart';

import '../../support/camera_harness.dart';
import 'package:gremote/camera/http/camera_api.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/platform/device_api.g.dart';

const photo = CameraFile(dir: '100RICOH', file: 'R0000001.JPG');
const roll = CameraIndexedRoll(
    id: '11111111111111111111111111111111',
    filmId: 66,
    target: 36,
    journalCount: 1,
    status: CameraRollStatus.closed,
    isLatest: true,
    photos: [
      CameraIndexedPhoto(
          file: photo,
          rollId: '11111111111111111111111111111111',
          frame: 1,
          target: 36)
    ]);

class _Gallery extends CameraGalleryService {
  _Gallery(this.image)
      : super(
            CameraApi(FakeCameraGateways().transport), CameraDeviceHostApi()) {
    for (final name in ['00004562', '00004563']) {
      final file = File('/tmp/r12-dng-preview-$name.jpg');
      if (file.existsSync())
        rawPreviews['141_1122/$name.DNG'] = file.readAsBytesSync();
    }
  }
  final Uint8List image;
  final rawPreviews = <String, Uint8List>{};
  @override
  Future<List<CameraFile>> photos() async =>
      [photo, const CameraFile(dir: '100RICOH', file: 'R0000002.JPG')];
  @override
  Future<Uint8List> thumbnail(CameraFile file,
          {bool Function()? isCurrent}) async =>
      rawPreviews[file.remoteId] ?? image;
}

class _Index extends CameraRollIndexController {
  @override
  CameraRollIndexState build() =>
      const CameraRollIndexState(latest: roll, rolls: [roll]);
  @override
  Future<void> refresh() async {}
  void use(CameraIndexedRoll value) {
    state = CameraRollIndexState(latest: value, rolls: [value]);
  }
}

class _Api implements CameraLiveApi {
  @override
  Future<CameraLiveManifest?> liveManifest(CameraFile jpeg) async =>
      CameraLiveManifest.parse({
        'version': 1,
        'jpeg': {'directory': jpeg.dir, 'file': jpeg.file, 'sha256': 'a' * 64},
        'clip': {
          'format': 'mp4',
          'directory': jpeg.dir,
          'file': '${jpeg.baseName}.mp4',
          'bytes': 16,
          'sha256': 'b' * 64
        }
      }, jpeg);
  @override
  Future<void> liveClip(CameraLiveManifest manifest,
          Future<void> Function(Uint8List) receive) =>
      throw UnimplementedError();
}

class _Native extends MotionPhotoApi {
  _Native(this.image);
  final Uint8List image;
  final controls = <String>[];
  int position = 0;
  bool playing = false;
  @override
  Future<MotionVideoPlayer> openPlayer(String path) async =>
      const MotionVideoPlayer(42, 600, 400, 3000);
  @override
  Future<MotionVideoInfo> inspectVideo(String path) async =>
      MotionVideoInfo(3000, List.filled(6, image));
  @override
  Future<Map<String, Object?>> playerControl(int id, String action,
      {int? positionMs}) async {
    controls.add(action);
    if (positionMs != null) position = positionMs;
    playing = action == 'play';
    return {};
  }

  @override
  Future<Map<String, Object?>> playerStatus(int id) async =>
      {'positionMs': position, 'playing': playing};
  @override
  Future<String> exportVideo(String path, String name) async {
    controls.add('exportVideo');
    return 'content://video/1';
  }
}

class _Media extends CameraLiveMedia {
  _Media(this.pair, _Native native) : super(native: native);
  final PreparedCameraLivePhoto pair;
  @override
  Future<PreparedCameraLivePhoto?> prepare(CameraLiveApi api, CameraFile photo,
          {required bool Function() isCurrent,
          String? sourceCameraKey}) async =>
      PreparedCameraLivePhoto(
          pair.directory, pair.jpeg, pair.mp4, pair.presentationTimestampUs,
          sourceCameraKey: sourceCameraKey);
}

void main() {
  testWidgets(
      'production album views render with Live unavailable',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = Platform.environment['CAPTURE_R12_UI'] == '1';
    if (capture) {
      final font = File('/System/Library/Fonts/STHeiti Medium.ttc');
      if (font.existsSync())
        await (FontLoader('R12Chinese')
              ..addFont(
                  Future.value(ByteData.sublistView(font.readAsBytesSync()))))
            .load();
    }
    if (capture) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(File(
                    '/Users/zhaoo/development/flutter-gremote-3.50.0/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
                .readAsBytesSync()))))
          .load();
    }
    if (capture) {
      await (FontLoader('GRemoteEditorial')
            ..addFont(Future.value(ByteData.sublistView(
                File('assets/fonts/gremote_editorial_serif.ttf')
                    .readAsBytesSync()))))
          .load();
      final chinese =
          File('/System/Library/Fonts/STHeiti Medium.ttc').readAsBytesSync();
      for (final alias in [
        'Noto Serif CJK SC',
        'Noto Sans CJK SC',
        'PingFang SC'
      ]) {
        await (FontLoader(alias)
              ..addFont(Future.value(ByteData.sublistView(chinese))))
            .load();
      }
    }
    final image = File('assets/images/street_moment.jpg').readAsBytesSync();
    final root = Directory.systemTemp.createTempSync('r12-player-fixture-');
    addTearDown(() async {
      try {
        await root.delete(recursive: true);
      } on FileSystemException {
        if (await root.exists()) rethrow;
      }
    });
    final jpeg = File('${root.path}/still.jpg')..writeAsBytesSync(image);
    final mp4 = File('${root.path}/motion.mp4')
      ..writeAsBytesSync(List.filled(16, 1));
    final pair = PreparedCameraLivePhoto(root, jpeg, mp4, 1500000);
    final native = _Native(image);
    final api = _Api();
    final harness = await CameraHarness.create(overrides: [
      cameraGalleryServiceProvider.overrideWithValue(_Gallery(image)),
      importHistoryProvider.overrideWith((ref) async => []),
      cameraRollIndexProvider.overrideWith(_Index.new),
      cameraFilmCatalogProvider.overrideWith((ref) async =>
          CameraFilmCatalog.fromJson(jsonDecode(
              File('assets/films/camera-profiles/leica-gr3-catalog.json')
                  .readAsStringSync()) as Map<String, dynamic>)),
      cameraLiveApiProvider.overrideWithValue(api),
      savedLivePhotosProvider.overrideWith((ref) async => []),
      companionHotspotPairingProvider.overrideWith((ref) async => null),
      companionIdentityHydrationProvider.overrideWith((ref) async {}),
      cameraLiveMediaProvider.overrideWithValue(_Media(pair, native)),
      liveCameraArchiveKeyProvider.overrideWithValue('fixture-camera')
    ]);
    addTearDown(harness.dispose);
    await tester.runAsync(harness.connect);
    final boundary = GlobalKey();
    Future<void> pump(Widget child) async {
      final theme = capture
          ? GRemoteTheme.dark.copyWith(
              textTheme:
                  GRemoteTheme.dark.textTheme.apply(fontFamily: 'R12Chinese'),
              appBarTheme: GRemoteTheme.dark.appBarTheme.copyWith(
                  titleTextStyle:
                      const TextStyle(fontFamily: 'R12Chinese', fontSize: 20)))
          : GRemoteTheme.dark;
      Widget app;
      if (child is LibraryPage || child is HomePage) {
        final router = GoRouter(
            initialLocation: child is HomePage ? '/home' : '/library',
            routes: [
              StatefulShellRoute.indexedStack(
                  builder: (context, state, shell) =>
                      GRemoteShell(navigationShell: shell),
                  branches: [
                    for (final path in [
                      '/home',
                      '/library',
                      '/shoot',
                      '/camera'
                    ])
                      StatefulShellBranch(routes: [
                        GoRoute(
                            path: path,
                            builder: (_, __) => path ==
                                    (child is HomePage ? '/home' : '/library')
                                ? child
                                : const SizedBox.shrink())
                      ])
                  ])
            ]);
        addTearDown(router.dispose);
        app = MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: theme,
            routerConfig: router);
      } else {
        app = MaterialApp(
            debugShowCheckedModeBanner: false, theme: theme, home: child);
      }
      await tester.pumpWidget(UncontrolledProviderScope(
          container: harness.container,
          child: RepaintBoundary(key: boundary, child: app)));
      await tester.runAsync(() async {
        await precacheImage(const AssetImage('assets/images/home_header.jpg'),
            boundary.currentContext!);
        await precacheImage(
            const AssetImage('assets/images/gremote_brand_editorial.png'),
            boundary.currentContext!);
        await precacheImage(
            const AssetImage('assets/films/camera-icons/66.png'),
            boundary.currentContext!);
        await precacheImage(MemoryImage(image), boundary.currentContext!);
        await precacheImage(ResizeImage(MemoryImage(image), width: 600),
            boundary.currentContext!);
        for (final indexed in harness.container
            .read(cameraRollIndexProvider)
            .rolls
            .expand((roll) => roll.photos)
            .where((photo) => photo.file.extension == 'DNG')) {
          final bytes =
              (harness.container.read(cameraGalleryServiceProvider) as _Gallery)
                      .rawPreviews[indexed.file.remoteId] ??
                  image;
          await precacheImage(ResizeImage(MemoryImage(bytes), width: 600),
              boundary.currentContext!);
        }
        if (await jpeg.exists())
          await precacheImage(ResizeImage(FileImage(jpeg), width: 1200),
              boundary.currentContext!);
      });
      await tester.pumpAndSettle();
    }

    Future<void> shot(String name) async {
      if (!capture) return;
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final png = await render.toImage(pixelRatio: 2);
        final data = await png.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory('/tmp/r12-ui-captures')
          ..createSync(recursive: true);
        File('${output.path}/$name.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
        png.dispose();
      });
    }

    await pump(const LibraryPage(initialSection: AlbumSection.rolls));
    expect(find.byKey(const ValueKey('latest-camera-roll')), findsOneWidget);
    await shot('01-album-rolls');
    await pump(const CameraRollDetailPage(roll));
    expect(find.text('保存整卷'), findsOneWidget);
    await shot('02-camera-roll-detail');
    const unread = CameraIndexedRoll(
        id: '11111111111111111111111111111111',
        filmId: 66,
        target: 36,
        journalCount: 2,
        status: CameraRollStatus.closed,
        isLatest: true);
    final fixtureIndex =
        harness.container.read(cameraRollIndexProvider.notifier) as _Index;
    fixtureIndex.use(unread);
    await pump(const CameraRollDetailPage(unread));
    expect(find.text('保存整卷'), findsNothing);
    await shot('05-unread-camera-roll');
    if (capture &&
        File('/tmp/r12-dng-preview-00004562.jpg').existsSync() &&
        File('/tmp/r12-dng-preview-00004563.jpg').existsSync()) {
      const recovered = CameraIndexedRoll(
          id: '11111111111111111111111111111111',
          filmId: 66,
          target: 36,
          journalCount: 2,
          status: CameraRollStatus.closed,
          isLatest: true,
          photos: [
            CameraIndexedPhoto(
                file: CameraFile(dir: '141_1122', file: '00004562.DNG'),
                rollId: '11111111111111111111111111111111',
                frame: 1,
                target: 36),
            CameraIndexedPhoto(
                file: CameraFile(dir: '141_1122', file: '00004563.DNG'),
                rollId: '11111111111111111111111111111111',
                frame: 2,
                target: 36)
          ]);
      fixtureIndex.use(recovered);
      await pump(const CameraRollDetailPage(recovered));
      await shot('11-verified-raw-originals');
      await tester.tap(find
          .byKey(const ValueKey('camera-gallery-photo-141_1122/00004562.DNG')));
      await tester.pumpAndSettle();
      await shot('12-raw-single-photo');
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();

      fixtureIndex.use(unread);
    }

    final phoneCatalog = FilmCatalog.fromJson(
        jsonDecode(File('assets/films/catalog.json').readAsStringSync())
            as Map<String, dynamic>);
    final localRoll = await harness.container
        .read(filmRepositoryProvider)
        .createRoll(
            name: '111', targetCount: 36, recipe: phoneCatalog.recipe(33));
    harness.container.read(filmRollRevisionProvider.notifier).state++;
    await pump(const LibraryPage(initialSection: AlbumSection.rolls));
    await shot('06-compact-roll-list');
    await pump(RollDetailPage(rollId: localRoll.id));
    await shot('07-empty-phone-roll');
    await tester.tap(find.byTooltip('胶卷更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除胶卷'));
    await tester.pumpAndSettle();
    await shot('08-delete-confirmation');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await pump(const HomePage());
    await shot('09-home-connected');
    await tester.scrollUntilVisible(find.text('位置记录'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('位置记录'));
    await tester.pumpAndSettle();
    await shot('10-location-sheet');
    fixtureIndex.use(roll);

    await pump(const LibraryPage(initialSection: AlbumSection.live));
    await shot('03-live-gallery');
    await pump(const CameraLivePhotoPage(photo));
    expect(find.textContaining('Live 暂不可用'), findsOneWidget);
    await shot('04-live-unavailable');
    expect(native.controls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

  });
}
