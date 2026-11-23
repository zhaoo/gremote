import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/camera_roll_index.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/connection/connection_state.dart';
import 'package:gremote/camera/gateway/native_gateways.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/camera/model/camera_identity.dart';
import 'package:gremote/camera/model/camera_snapshot.dart';
import 'package:gremote/camera/recipe/shooting_recipe.dart';
import 'package:gremote/features/film_workbench/camera_roll_detail_page.dart';
import 'package:gremote/features/film_workbench/roll_archive_actions.dart';
import 'package:gremote/features/library/live_gallery_page.dart';
import 'package:gremote/features/library/camera_gallery.dart';
import 'package:gremote/film/store/film_repository.dart';
import 'package:gremote/platform/device_api.g.dart';
import '../../support/test_darkroom.dart';

const _id = '0102030405060708090a0b0c0d0e0f10';
const _files = [
  CameraFile(dir: '141_1122', file: '00004562.DNG'),
  CameraFile(dir: '141_1122', file: '00004563.DNG')
];

class _Ready extends ConnectionController {
  @override
  CameraConnectionState build() => const ConnectionReady(
      snapshot: CameraSnapshot(
          identity: CameraIdentity(model: 'RICOH GR III', firmware: '2.10'),
          battery: CameraBattery(level: 82, acPowered: false)),
      firmwareWarning: false,
      wifiOnly: true);
}

class _Index extends CameraRollIndexController {
  @override
  CameraRollIndexState build() =>
      const CameraRollIndexState(latest: _roll, rolls: [_roll]);
}

const _roll = CameraIndexedRoll(
    id: _id,
    target: 36,
    filmId: 66,
    journalCount: 2,
    status: CameraRollStatus.closed,
    isLatest: true,
    photos: [
      CameraIndexedPhoto(
          file: CameraFile(dir: '141_1122', file: '00004562.DNG'),
          rollId: _id,
          frame: 1,
          target: 36),
      CameraIndexedPhoto(
          file: CameraFile(dir: '141_1122', file: '00004563.DNG'),
          rollId: _id,
          frame: 2,
          target: 36)
    ]);
String _marker(int frame) {
  final bytes = Uint8List(32)..setAll(0, [0x4d, 0x31, 0x30, 0x52]);
  bytes.setAll(4, [
    for (var i = 0; i < _id.length; i += 2)
      int.parse(_id.substring(i, i + 2), radix: 16)
  ]);
  final data = ByteData.sublistView(bytes)
    ..setUint32(20, frame, Endian.little)
    ..setUint32(24, 36, Endian.little);
  data.setUint32(28, exposureRecipeCrc(bytes, 28), Endian.little);
  return bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
}

void main() {
  testWidgets(
      'unavailable DNG thumbnail keeps a RAW placeholder and never requests a sibling JPG',
      (tester) async {
    final requests = <CameraFile>[];
    await tester.pumpWidget(ProviderScope(
        overrides: [
          cameraArchiveStableKeyProvider.overrideWithValue('camera-a'),
          cameraAlbumThumbnailProvider.overrideWith((ref, key) async {
            requests.add(key.photo);
            return Uint8List.fromList([0, 1, 2]);
          })
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: CameraAlbumThumbnail(
                    CameraFile(dir: '141_1122', file: '00004562.DNG'))))));
    await tester.pumpAndSettle();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pumpAndSettle();
    expect(requests, [_files.first]);
    expect(find.byIcon(Icons.raw_on_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'verified RAW roll badges and whole-save archive only the two tagged DNG originals',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    final gateways = NativeCameraGateways();
    addTearDown(gateways.dispose);
    final messenger = tester.binding.defaultBinaryMessenger;
    const codec = CameraDeviceHostApi.pigeonChannelCodec;
    final downloaded = <String>[], requested = <String>[];
    void host(String method, Future<Object?> Function(Object?) handler) {
      final channel = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.gremote.CameraDeviceHostApi.$method', codec);
      messenger.setMockDecodedMessageHandler<Object?>(channel, handler);
      addTearDown(() => messenger.setMockDecodedMessageHandler(channel, null));
    }

    host('androidSdkInt', (_) async => [34]);
    host('cameraRequest', (message) async {
      final path = (message as List)[1] as String;
      requested.add(path);
      return [
        NativeHttpResponse(
            statusCode: 200, headers: {}, body: base64Decode(_jpeg))
      ];
    });
    host('downloadPhoto', (message) async {
      final file = (message as List)[1] as String;
      downloaded.add(file);
      final frame = file == _files.first.file ? 1 : 2;
      await messenger.handlePlatformMessage(
          'dev.flutter.pigeon.gremote.CameraDeviceFlutterApi.onNativeEvent',
          codec.encodeMessage([
            'photoRecordedFilm',
            jsonEncode({
              'id': '141_1122/$file',
              'hash': (frame == 1 ? 'a' : 'b') * 64,
              'rollFrame': _marker(frame)
            })
          ]),
          null);
      return ['content://media/external/images/media/${812 + frame}'];
    });
    await tester.pumpWidget(ProviderScope(overrides: [
      ...env.overrides,
      cameraGatewaysProvider.overrideWithValue(gateways),
      connectionControllerProvider.overrideWith(_Ready.new),
      cameraRollIndexProvider.overrideWith(_Index.new),
      cameraArchiveStableKeyProvider.overrideWithValue('camera-a')
    ], child: const MaterialApp(home: CameraRollDetailPage(_roll))));
    await tester.pumpAndSettle();
    expect(find.text('RAW'), findsNWidgets(2));
    await tester.tap(find.text('保存整卷'));
    await tester.pumpAndSettle();
    expect(downloaded, ['00004562.DNG', '00004563.DNG']);
    expect(requested.any((path) => path.contains('.JPG')), isFalse);
    final repo = FilmRepository(env.db),
        items = await FilmRepository(env.db).listItems(_id);
    expect((await repo.rolls()).single.confirmedCount, 2);
    expect(items.map((item) => item.frameNumber), [1, 2]);
    expect(items.map((item) => item.files.single),
        ['00004562.DNG', '00004563.DNG']);
    expect(items.map((item) => item.mediaId), [813, 814]);
    expect(find.text('读取动态照片'), findsNothing);
    Navigator.of(tester.element(find.byType(CameraGallery))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看已保存的 2 张'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AlbumTag, 'RAW'), findsNWidgets(2));
    expect(find.text('2 / 36 张 · 从机身归档'), findsOneWidget);
  });
}

const _jpeg =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof'
    'Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAACAAIBAREA/8QAFAAB'
    'AAAAAAAAAAAAAAAAAAAAB//EABwQAAICAgMAAAAAAAAAAAAAAAECBQYDBAASYf/aAAgBAQAA'
    'PwBWg6lW3gI13r0SzNq4iSdLGST1HnP/2Q==';
