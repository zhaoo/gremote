import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/model/camera_snapshot.dart';
import 'package:gremote/camera/protocol/ble_codecs.dart';

void main() {
  group('BLE string codec', () {
    test('decodes UTF-8 and strips every trailing NUL', () {
      expect(
        decodeNullTerminatedUtf8(
          Uint8List.fromList([..."RICOH GR III".codeUnits, 0, 0]),
        ),
        'RICOH GR III',
      );
    });

    test('preserves embedded NUL as invalid data', () {
      expect(
        () => decodeNullTerminatedUtf8(
          Uint8List.fromList([..."GR".codeUnits, 0, ..."III".codeUnits]),
        ),
        throwsFormatException,
      );
    });
  });

  group('battery codec', () {
    test('decodes battery level and source', () {
      expect(
        decodeBattery(Uint8List.fromList([82, 0])),
        const CameraBattery(level: 82, acPowered: false),
      );
      expect(
        decodeBattery(Uint8List.fromList([100, 1])),
        const CameraBattery(level: 100, acPowered: true),
      );
    });

    test('rejects malformed battery payloads', () {
      expect(
        () => decodeBattery(Uint8List.fromList([82])),
        throwsFormatException,
      );
      expect(
        () => decodeBattery(Uint8List.fromList([101, 0])),
        throwsFormatException,
      );
      expect(
        () => decodeBattery(Uint8List.fromList([80, 2])),
        throwsFormatException,
      );
    });
  });

  group('operation request codec', () {
    test('encodes AF shutter start and stop', () {
      expect(
        encodeOperationRequest(start: true, autoFocus: true),
        Uint8List.fromList([1, 1]),
      );
      expect(
        encodeOperationRequest(start: false, autoFocus: true),
        Uint8List.fromList([2, 1]),
      );
    });

    test('encodes shutter without autofocus', () {
      expect(
        encodeOperationRequest(start: true, autoFocus: false),
        Uint8List.fromList([1, 0]),
      );
    });
  });
}
