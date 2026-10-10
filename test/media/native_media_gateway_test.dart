import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/media/local/media_gateway.dart';
import 'package:gremote/media/local/native_media_gateway.dart';
import 'package:gremote/platform/media_api.g.dart';

class _FakeHostApi extends MediaHostApi {
  Object? error;

  @override
  Future<NativeMediaAccess> access() async => NativeMediaAccess.partial;

  @override
  Future<List<NativeExifSummary>> readExif(List<int> ids) async {
    if (error != null) throw error!;
    return [
      NativeExifSummary(
        id: 7,
        width: 6000,
        height: 4000,
        orientation: 6,
        model: 'RICOH GR III',
        fNumber: 2.8,
        exposureTime: 0.004,
        iso: 200,
        focal35: 28,
        takenAt: '2026:10:10 08:30:00',
        hasGps: true,
      ),
    ];
  }

  @override
  Future<String> publishExport(String tempPath, int sourceId,
          String displayName, bool keepGps, int width, int height) async =>
      throw PlatformException(code: 'storageFull', message: 'No space');
}

void main() {
  late _FakeHostApi host;
  late NativeMediaGateway gateway;

  setUp(() {
    host = _FakeHostApi();
    gateway = NativeMediaGateway(host);
  });

  test('maps access state', () async {
    expect(await gateway.access(), MediaAccess.partial);
  });

  test('maps EXIF summaries to PhotoMeta keyed by id', () async {
    final metas = await gateway.readExif([7]);
    final meta = metas[7]!;
    expect(meta.orientedWidth, 4000);
    expect(meta.modelLabel, 'RICOH GR III');
    expect(meta.shutterLabel, '1/250s');
    expect(meta.focalLabel, '28mm');
    expect(meta.hasGps, isTrue);
  });

  test('translates platform errors into MediaException', () async {
    await expectLater(
      gateway.publishExport(
          tempPath: '/t.jpg',
          sourceId: 7,
          displayName: 'a.jpg',
          keepGps: false,
          width: 1,
          height: 1),
      throwsA(isA<MediaException>()
          .having((e) => e.code, 'code', 'storageFull')
          .having((e) => e.message, 'message', 'No space')),
    );
  });
}
