import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/camera/companion/camera_roll_index.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/connection/connection_state.dart';
import 'package:gremote/camera/gateway/ble_gateway.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/camera/http/camera_api.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/camera/model/camera_identity.dart';
import 'package:gremote/camera/model/camera_snapshot.dart';
import 'package:gremote/camera/recipe/shooting_recipe.dart';
import 'package:gremote/features/film_workbench/camera_roll_detail_page.dart';
import 'package:gremote/features/film_workbench/roll_archive_actions.dart';
import 'package:gremote/features/library/camera_gallery.dart';
import 'package:gremote/platform/device_api.g.dart';
import '../../support/test_darkroom.dart';

const _id = '11111111111111111111111111111111';
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
  void otherCamera() => state = _ready('camera-b');
  void sameCamera() => state = _ready('camera-a');
  void offline() => state = const ConnectionIdle();
}

class _Index extends CameraRollIndexController {
  _Index(this.roll);
  final CameraIndexedRoll roll;
  @override
  CameraRollIndexState build() =>
      CameraRollIndexState(latest: roll, rolls: [roll]);
}

String _marker(int frame) {
  final bytes = Uint8List(32)
    ..setAll(0, [0x4d, 0x31, 0x30, 0x52])
    ..setAll(4, List.filled(16, 0x11));
  final data = ByteData.sublistView(bytes)
    ..setUint32(20, frame, Endian.little)
    ..setUint32(24, 36, Endian.little);
  data.setUint32(28, exposureRecipeCrc(bytes, 28), Endian.little);
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class _Gallery extends CameraGalleryService {
  _Gallery(this.bytes, this.source, this.output)
      : super(CameraApi(FakeCameraGateways().transport), CameraDeviceHostApi(),
            events: output.stream);
  final Uint8List bytes;
  final String? Function() source;
  final StreamController<CameraDeviceEvent> output;
  final saved = <CameraFile>[], thumbs = <String>[];
  bool noPreview = false;
  @override
  Future<List<CameraFile>> photos() async =>
      throw StateError('A roll must only use its verified index files');

  @override
  Future<Uint8List> thumbnail(CameraFile file,
      {bool Function()? isCurrent}) async {
    if (isCurrent?.call() == false) throw StateError('changed');
    thumbs.add('${source()}:${file.remoteId}');
    if (noPreview) throw StateError('RAW preview unavailable');
    return bytes;
  }

  @override
  Future<String> download(CameraFile file, {bool Function()? isCurrent}) async {
    if (isCurrent?.call() == false) throw StateError('changed');
    saved.add(file);
    final frame = file.baseName.endsWith('1') ? 1 : 2;
    output.add(CameraDeviceEvent(
        type: 'photoRecordedFilm',
        jsonPayload: jsonEncode({
          'id': file.remoteId,
          'hash': '$frame' * 64,
          'rollFrame': _marker(frame)
        })));
    return 'content://media/external/images/media/${500 + frame}';
  }
}

void main() {
  for (final format in ['JPG', 'RAW', 'RAW+JPG']) {
    for (final multiple in [false, true]) {
      testWidgets(
          'roll uses ordinary downloader: $format ${multiple ? "multi" : "single"} selection',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final bytes = File('assets/images/street_moment.jpg').readAsBytesSync();
        final env = await TestDarkroom.create();
        addTearDown(env.close);
        final events =
            StreamController<CameraDeviceEvent>.broadcast(sync: true);
        addTearDown(events.close);
        final originals = [
          for (final n in [1, 2])
            for (final ext in ['JPG', 'DNG'])
              CameraFile(dir: '100RICOH', file: 'R000000$n.$ext')
        ];
        final roll = CameraIndexedRoll(
            id: _id,
            target: 36,
            journalCount: 2,
            filmId: 66,
            photos: [
              for (var i = 0; i < originals.length; i++)
                CameraIndexedPhoto(
                    file: originals[i],
                    rollId: _id,
                    frame: i ~/ 2 + 1,
                    target: 36)
            ]);
        late final ProviderContainer container;
        final gallery = _Gallery(bytes,
            () => container.read(cameraArchiveStableKeyProvider), events);
        container = ProviderContainer(overrides: [
          ...env.overrides,
          connectionControllerProvider.overrideWith(_Connection.new),
          cameraRollIndexProvider.overrideWith(() => _Index(roll)),
          cameraGalleryServiceProvider.overrideWithValue(gallery)
        ]);
        addTearDown(container.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
                theme: GRemoteTheme.dark, home: CameraRollDetailPage(roll))));
        await tester.pumpAndSettle();
        expect(find.byType(CameraGallery), findsOneWidget);
        expect(find.text('2 张'), findsOneWidget);
        await tester.tap(find.text('多选'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(
            const ValueKey('camera-gallery-photo-100RICOH/R0000001.JPG')));
        if (multiple) {
          await tester.tap(find.byKey(
              const ValueKey('camera-gallery-photo-100RICOH/R0000002.JPG')));
        }
        await tester.pumpAndSettle();
        expect(find.text('已选 ${multiple ? 2 : 1} 张'), findsNWidgets(2));
        await tester.tap(find.text(format));
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存原图'));
        await tester.pumpAndSettle();
        final expected = originals
            .where((f) =>
                (multiple || f.baseName.endsWith('1')) &&
                (format == 'RAW+JPG' ||
                    (format == 'RAW'
                        ? f.extension == 'DNG'
                        : f.extension == 'JPG')))
            .toList();
        expect(gallery.saved.map((f) => f.remoteId),
            unorderedEquals(expected.map((f) => f.remoteId)));
        expect(
            gallery.thumbs.every((id) => id.startsWith('camera-a:')), isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'roll tap shares ordinary preview and per-file download, rejects changed camera',
      (tester) async {
    final bytes = File('assets/images/street_moment.jpg').readAsBytesSync();
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    final events = StreamController<CameraDeviceEvent>.broadcast(sync: true);
    addTearDown(events.close);
    const jpeg = CameraFile(dir: '100RICOH', file: 'R0000001.JPG');
    const raw = CameraFile(dir: '100RICOH', file: 'R0000001.DNG');
    const roll = CameraIndexedRoll(id: _id, target: 36, photos: [
      CameraIndexedPhoto(file: jpeg, rollId: _id, frame: 1, target: 36),
      CameraIndexedPhoto(file: raw, rollId: _id, frame: 1, target: 36)
    ]);
    late final ProviderContainer container;
    final gallery = _Gallery(
        bytes, () => container.read(cameraArchiveStableKeyProvider), events);
    container = ProviderContainer(overrides: [
      ...env.overrides,
      connectionControllerProvider.overrideWith(_Connection.new),
      cameraRollIndexProvider.overrideWith(() => _Index(roll)),
      cameraGalleryServiceProvider.overrideWithValue(gallery)
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CameraRollDetailPage(roll))));
    await tester.pumpAndSettle();
    await tester.tap(find
        .byKey(const ValueKey('camera-gallery-photo-100RICOH/R0000001.JPG')));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text(jpeg.file), findsOneWidget);
    expect(find.text(raw.file), findsOneWidget);
    await tester.tap(find.byTooltip('下载 DNG'));
    await tester.pumpAndSettle();
    expect(gallery.saved, [raw]);
    await tester.tap(find
        .byKey(const ValueKey('camera-gallery-photo-100RICOH/R0000001.JPG')));
    await tester.pumpAndSettle();
    final stale = tester
        .widget<IconButton>(find
            .byWidgetPredicate((w) => w is IconButton && w.tooltip == '下载 JPG'))
        .onPressed!;
    (container.read(connectionControllerProvider.notifier) as _Connection)
        .otherCamera();
    await tester.pumpAndSettle();
    stale();
    await tester.pumpAndSettle();
    expect(gallery.saved, [raw]);
    expect(gallery.thumbs.where((id) => id.startsWith('camera-b:')), isEmpty);
  });
}
