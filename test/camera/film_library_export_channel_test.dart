import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/platform/device_api.g.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.gremote.CameraDeviceHostApi.exportFilmLibrary',
      CameraDeviceHostApi.pigeonChannelCodec);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockDecodedMessageHandler(channel, null));

  test('explicit library export sends exact bytes and returns saved receipt',
      () async {
    final bytes = Uint8List.fromList([77, 49, 48, 86, 83, 68, 49, 0]);
    messenger.setMockDecodedMessageHandler<Object?>(channel, (message) async {
      expect(message, [bytes]);
      return [true];
    });
    expect(await CameraDeviceHostApi().exportFilmLibrary(bytes), isTrue);
  });

  test('cancelled system export returns false without a success receipt',
      () async {
    messenger.setMockDecodedMessageHandler<Object?>(
        channel, (message) async => [false]);
    expect(
        await CameraDeviceHostApi().exportFilmLibrary(Uint8List(0)), isFalse);
  });

  test('native validation failure stays an error instead of successful export',
      () async {
    messenger.setMockDecodedMessageHandler<Object?>(
        channel, (message) async => ['invalidFilmLibrary', '胶卷库格式无效', null]);
    expect(
        CameraDeviceHostApi().exportFilmLibrary(Uint8List(0)),
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', 'invalidFilmLibrary')));
  });
}
