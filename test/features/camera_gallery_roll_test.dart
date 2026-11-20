import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/connection/connection_state.dart';
import 'package:gremote/camera/gateway/native_gateways.dart';
import 'package:gremote/camera/model/camera_identity.dart';
import 'package:gremote/camera/model/camera_snapshot.dart';
import 'package:gremote/features/library/camera_gallery.dart';
import 'package:gremote/film/model/film_roll.dart';
import 'package:gremote/film/store/film_repository.dart';
import 'package:gremote/platform/device_api.g.dart';

import '../support/test_darkroom.dart';

class _Ready extends ConnectionController {
  @override
  CameraConnectionState build() => const ConnectionReady(
        snapshot: CameraSnapshot(
          identity: CameraIdentity(model: 'RICOH GR III', firmware: '2.10'),
          battery: CameraBattery(level: 82, acPowered: false),
        ),
        firmwareWarning: false,
        wifiOnly: true,
      );
}

void main() {
  testWidgets('gallery archives native M10R events and merges JPG plus DNG',
      (tester) async {
    const dir = '100RICOH';
    const jpg = 'R0000021.JPG';
    const dng = 'R0000021.DNG';
    const marker =
        '4d3130520102030405060708090a0b0c0d0e0f10070000000c0000003db3a575';
    const hostPrefix = 'dev.flutter.pigeon.gremote.CameraDeviceHostApi';
    const eventChannel =
        'dev.flutter.pigeon.gremote.CameraDeviceFlutterApi.onNativeEvent';
    const codec = CameraDeviceHostApi.pigeonChannelCodec;
    final messenger = tester.binding.defaultBinaryMessenger;
    final env = await TestDarkroom.create();
    final gateways = NativeCameraGateways();
    addTearDown(env.close);
    addTearDown(gateways.dispose);
    final downloads = <String>[];
    void host(String method, Future<Object?> Function(Object?) handler) {
      final channel =
          BasicMessageChannel<Object?>('$hostPrefix.$method', codec);
      messenger.setMockDecodedMessageHandler<Object?>(channel, handler);
      addTearDown(() => messenger.setMockDecodedMessageHandler(channel, null));
    }

    host('androidSdkInt', (_) async => [34]);
    host('cameraRequest', (message) async {
      final path = (message as List)[1] as String;
      final bytes = path == '/v1/photos'
          ? Uint8List.fromList(utf8.encode(jsonEncode({
              'dirs': [
                {
                  'name': dir,
                  'files': [dng, jpg]
                }
              ]
            })))
          : base64Decode(_jpeg);
      return [NativeHttpResponse(statusCode: 200, headers: {}, body: bytes)];
    });
    host('downloadPhoto', (message) async {
      final args = message as List;
      expect(args[0], dir);
      final file = args[1] as String;
      downloads.add(file);
      await messenger.handlePlatformMessage(
          eventChannel,
          codec.encodeMessage([
            'photoRecordedFilm',
            jsonEncode({
              'id': '$dir/$file',
              'hash': (file == jpg ? 'a' : 'b') * 64,
              'rollFrame': marker,
            }),
          ]),
          null);
      return [
        'content://media/external/images/media/${file == jpg ? 812 : 813}'
      ];
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...env.overrides,
        cameraGatewaysProvider.overrideWithValue(gateways),
        connectionControllerProvider.overrideWith(_Ready.new),
      ],
      child: const MaterialApp(home: Scaffold(body: CameraGallery())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('R0000021'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存全部格式 · 2 个文件'));
    await tester.pumpAndSettle();
    expect(downloads, [dng, jpg]);
    expect(find.text('保存完成 · 成功 2 / 2 个文件'), findsOneWidget);
    final repo = FilmRepository(env.db);
    final roll = (await repo.rolls()).single;
    final frames = await repo.listItems(roll.id);
    expect(roll.confirmedCount, 1);
    expect(roll.targetCount, 12);
    expect(frames.single.frameNumber, 7);
    expect(frames.single.files, [dng, jpg]);
    expect(frames.single.mediaId, 812);
    expect(frames.single.confidence, RecipeConfidence.unverified);
  });
}

const _jpeg =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof'
    'Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAACAAIBAREA/8QAFAAB'
    'AAAAAAAAAAAAAAAAAAAAB//EABwQAAICAgMAAAAAAAAAAAAAAAECBQYDBAASYf/aAAgBAQAA'
    'PwBWg6lW3gI13r0SzNq4iSdLGST1HnP/2Q==';
