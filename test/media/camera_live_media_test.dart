import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/camera_live_manifest.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/media/local/camera_live_media.dart';

const jpeg = CameraFile(dir: '100RICOH', file: 'R0000021.JPG');
final clip = Uint8List.fromList(List<int>.generate(64, (index) => index));
final jpegHash = 'ab' * 32;

Map<String, dynamic> manifest({String? digest, String format = 'm10l'}) => {
      'version': 1,
      'jpeg': {
        'directory': '100RICOH',
        'file': 'R0000021.JPG',
        'sha256': jpegHash,
      },
      'clip': {
        'directory': 'LIVE',
        'file': 'clip.$format',
        'format': format,
        'bytes': clip.length,
        'sha256': digest ?? sha256.convert(clip).toString(),
      },
      'presentationTimestampUs': 120000,
    };

class CameraWire implements CameraLiveApi {
  CameraWire(this.wire);
  final Map<String, dynamic>? wire;

  @override
  Future<CameraLiveManifest?> liveManifest(CameraFile photo) async =>
      wire == null ? null : CameraLiveManifest.parse(wire!, photo);

  @override
  Future<void> liveClip(CameraLiveManifest manifest,
      Future<void> Function(Uint8List) receive) async {
    for (final offset in [0, 32]) {
      await receive(manifest.chunk({
        'offset': offset,
        'bytes': clip.length,
        'data': base64Encode(clip.sublist(offset, offset + 32)),
      }, offset));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('association preserves DCF identity and rejects drift or bad paths', () {
    expect(CameraLiveManifest.pathFor(jpeg),
        '/m10v/v1/live/100RICOH/R0000021/JPG');
    expect(
        () => CameraLiveManifest.pathFor(
            const CameraFile(dir: '../LIVE', file: 'R0000021.JPG')),
        throwsFormatException);
    expect(
        () => CameraLiveManifest.parse(manifest(),
            const CameraFile(dir: '100RICOH', file: 'R0000022.JPG')),
        throwsFormatException);
    final pair = CameraLiveManifest.parse(manifest(), jpeg);
    expect(
        () => pair
            .chunk({'offset': 0, 'bytes': 65, 'data': base64Encode(clip)}, 0),
        throwsFormatException);
    expect(
        () => pair
            .chunk({'offset': 0, 'bytes': 64, 'data': base64Encode(clip)}, 32),
        throwsFormatException);
  });

  test('verified input, playback and export share a single paired short clip',
      () async {
    final root = await Directory.systemTemp.createTemp('camera-live-test-');
    addTearDown(() => root.delete(recursive: true));
    final service = CameraLiveMedia(temporaryDirectory: () async => root);
    final calls = <String>[];
    final binding =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('gremote/motion_photo');
    addTearDown(() => binding.setMockMethodCallHandler(channel, null));
    binding.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'downloadJpeg':
          expect(call.arguments['directory'], jpeg.dir);
          expect(call.arguments['file'], jpeg.file);
          expect(call.arguments['sha256'], jpegHash);
          await File(call.arguments['jpegPath'] as String).writeAsBytes([1, 2]);
          return null;
        case 'transcodeM10l':
          expect(
              await File(call.arguments['inputPath'] as String).readAsBytes(),
              clip);
          expect(call.arguments['presentationTimestampUs'], 120000);
          await File(call.arguments['mp4Path'] as String).writeAsBytes([3, 4]);
          return 120000;
        case 'preview':
          expect(await File(call.arguments['mp4Path'] as String).readAsBytes(),
              [3, 4]);
          return null;
        case 'export':
          expect(call.arguments['presentationTimestampUs'], 120000);
          expect(call.arguments['displayName'], jpeg.file);
          return 'content://media/images/812';
      }
      fail('Unexpected native call: ${call.method}');
    });

    expect(await service.prepare(CameraWire(null), jpeg, isCurrent: () => true),
        isNull);
    expect(calls, isEmpty);
    await expectLater(
        service.prepare(CameraWire(manifest(digest: 'ff' * 32)), jpeg,
            isCurrent: () => true),
        throwsFormatException);
    expect(calls, ['downloadJpeg']);
    expect(await root.list().toList(), isEmpty);

    calls.clear();
    final prepared = (await service.prepare(CameraWire(manifest()), jpeg,
        isCurrent: () => true))!;
    await service.native.preview(prepared.mp4.path);
    final uri = await service.native.export(
        prepared.jpeg.path, prepared.mp4.path, jpeg.file,
        presentationTimestampUs: prepared.presentationTimestampUs);
    expect(uri, 'content://media/images/812');
    expect(calls, ['downloadJpeg', 'transcodeM10l', 'preview', 'export']);
    await prepared.dispose();
    expect(await root.list().toList(), isEmpty);
  });
}
