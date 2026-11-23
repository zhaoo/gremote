import 'dart:typed_data';
import 'dart:async';
import 'package:gremote/camera/gateway/camera_transport.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/camera_roll_index.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/connection/connection_state.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/camera/http/camera_api.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/camera/model/camera_identity.dart';
import 'package:gremote/camera/model/camera_snapshot.dart';
import 'package:gremote/features/film_workbench/camera_roll_detail_page.dart';
import 'package:gremote/features/film_workbench/roll_archive_actions.dart';
import 'package:gremote/features/library/camera_gallery.dart';
import 'package:gremote/features/library/live_gallery_page.dart';
import 'package:gremote/platform/device_api.g.dart';
import '../../support/test_darkroom.dart';

const _file = CameraFile(dir: '141_1122', file: '00004562.DNG');
const _rollA = CameraIndexedRoll(
    id: '11111111111111111111111111111111',
    target: 36,
    filmId: 66,
    journalCount: 1,
    photos: [
      CameraIndexedPhoto(
          file: _file,
          rollId: '11111111111111111111111111111111',
          frame: 1,
          target: 36)
    ]);
const _rollB = CameraIndexedRoll(
    id: '22222222222222222222222222222222',
    target: 36,
    filmId: 66,
    journalCount: 1,
    photos: [
      CameraIndexedPhoto(
          file: _file,
          rollId: '22222222222222222222222222222222',
          frame: 1,
          target: 36)
    ]);
ConnectionReady _ready(String key) => ConnectionReady(
    snapshot: const CameraSnapshot(
        identity: CameraIdentity(model: 'RICOH GR III', firmware: '2.10'),
        battery: CameraBattery(level: 80, acPowered: false)),
    firmwareWarning: false,
    wifiOnly: true,
    cameraKey: key);

class _Connection extends ConnectionController {
  @override
  CameraConnectionState build() => _ready('camera-a');
  void switchCamera() => state = _ready('camera-b');
}

class _Index extends CameraRollIndexController {
  _Index(this.reads);
  final List<String> reads;
  @override
  CameraRollIndexState build() =>
      const CameraRollIndexState(rolls: [_rollA], hasMore: true);
  void switchCamera() => state = const CameraRollIndexState(rolls: [_rollB]);
  @override
  Future<void> loadMore() async {
    reads.add('read');
  }

  @override
  Future<void> refresh() async {
    reads.add('read');
  }
}

class _Gallery extends CameraGalleryService {
  _Gallery(this.key)
      : super(CameraApi(FakeCameraGateways().transport), CameraDeviceHostApi());
  final String? Function() key;
  final thumbnails = <String>[], downloads = <String>[];
  @override
  Future<Uint8List> thumbnail(CameraFile file,
      {bool Function()? isCurrent}) async {
    if (isCurrent?.call() == false) throw StateError('changed');
    thumbnails.add('${key()}:${file.remoteId}');
    throw StateError('fixture preview unavailable');
  }

  @override
  Future<String> download(CameraFile file, {bool Function()? isCurrent}) async {
    downloads.add('${key()}:${file.remoteId}');
    throw StateError('fixture blocks saving');
  }
}

class _Transport implements CameraTransport {
  final calls = <String>[];
  @override
  Stream<Uint8List> get liveViewChunks => const Stream.empty();
  @override
  Future<CameraResponse> request(
      {required String method,
      required String path,
      Map<String, String> headers = const {},
      Uint8List? body}) async {
    calls.add(path);
    return CameraResponse(
        statusCode: 200, headers: const {}, body: Uint8List(0));
  }

  @override
  Future<void> startLiveView(String path) async {}
  @override
  Future<void> stopLiveView() async {}
}

class _Host extends CameraDeviceHostApi {
  final sdk = Completer<int>();
  int downloads = 0;
  @override
  Future<int> androidSdkInt() => sdk.future;
  @override
  Future<String> downloadPhoto(String directory, String file) async {
    downloads++;
    return 'content://saved';
  }
}

void main() {
  test(
      'queued thumbnail is discarded before transport when the source camera changes',
      () async {
    final transport = _Transport(),
        service = CameraGalleryService(
            CameraApi(_Transport()), CameraDeviceHostApi());
    final guarded = CameraGalleryService(CameraApi(transport), service.host);
    final release = Completer<void>();
    final holding = guarded.transferGate.originals(() => release.future);
    await pumpEventQueue();
    var source = 'camera-a';
    final rejected = expectLater(
        guarded.thumbnail(_file, isCurrent: () => source == 'camera-a'),
        throwsStateError);
    source = 'camera-b';
    release.complete();
    await holding;
    await rejected;
    expect(transport.calls, isEmpty);
  });
  test(
      'source change during permission lookup prevents native original download',
      () async {
    final host = _Host(),
        service = CameraGalleryService(CameraApi(_Transport()), _Host());
    final guarded = CameraGalleryService(service.api, host);
    var source = 'camera-a';
    final rejected = expectLater(
        guarded.download(_file, isCurrent: () => source == 'camera-a'),
        throwsStateError);
    source = 'camera-b';
    host.sdk.complete(34);
    await rejected;
    expect(host.downloads, 0);
  });
  testWidgets(
      'an A-bound transfer route never starts against already-connected B',
      (tester) async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    late final ProviderContainer container;
    final gallery =
        _Gallery(() => container.read(cameraArchiveStableKeyProvider));
    container = ProviderContainer(overrides: [
      ...env.overrides,
      connectionControllerProvider.overrideWith(_Connection.new),
      cameraGalleryServiceProvider.overrideWithValue(gallery)
    ]);
    addTearDown(container.dispose);
    (container.read(connectionControllerProvider.notifier) as _Connection)
        .switchCamera();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
            home: Scaffold(
                body: CameraGallery(
                    initialFiles: [_file],
                    startDownload: true,
                    sourceCameraKey: 'camera-a')))));
    await tester.pumpAndSettle();
    expect(gallery.downloads, isEmpty);
    expect(gallery.thumbnails, isEmpty);
    expect(find.text('相机已切换'), findsOneWidget);
  });

  testWidgets(
      'open A roll cannot download or request its same-name path from camera B',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    final reads = <String>[];
    late final ProviderContainer container;
    final gallery =
        _Gallery(() => container.read(cameraArchiveStableKeyProvider));
    container = ProviderContainer(overrides: [
      ...env.overrides,
      connectionControllerProvider.overrideWith(_Connection.new),
      cameraRollIndexProvider.overrideWith(() => _Index(reads)),
      cameraGalleryServiceProvider.overrideWithValue(gallery)
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CameraRollDetailPage(_rollA))));
    await tester.pumpAndSettle();
    expect(gallery.thumbnails, ['camera-a:${_file.remoteId}']);
    final oldSave = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '保存整卷'))
        .onPressed!;
    final oldMore = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '读取更多照片'))
        .onPressed!;
    gallery.thumbnails.clear();
    (container.read(connectionControllerProvider.notifier) as _Connection)
        .switchCamera();
    (container.read(cameraRollIndexProvider.notifier) as _Index).switchCamera();
    container.invalidate(cameraAlbumThumbnailProvider);
    await tester.pumpAndSettle();
    oldSave();
    oldMore();
    await tester.pumpAndSettle();
    expect(gallery.downloads, isEmpty);
    expect(gallery.thumbnails, isEmpty);
    expect(reads, isEmpty);
    expect(find.text('相机已切换'), findsOneWidget);
    expect(find.text('保存整卷'), findsNothing);
    expect(find.text('照片尚未读取'), findsNothing);
  });
}
