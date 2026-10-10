import 'dart:convert';
import 'dart:typed_data';

import '../model/camera_snapshot.dart';

String decodeNullTerminatedUtf8(Uint8List payload) {
  var end = payload.length;
  while (end > 0 && payload[end - 1] == 0) {
    end--;
  }
  final value = payload.sublist(0, end);
  if (value.contains(0)) {
    throw const FormatException('BLE string contains an embedded NUL');
  }
  return utf8.decode(value, allowMalformed: false);
}

CameraBattery decodeBattery(Uint8List payload) {
  if (payload.length != 2) {
    throw FormatException(
      'Battery payload must contain 2 bytes, got ${payload.length}',
    );
  }

  final level = payload[0];
  final source = payload[1];
  if (level > 100) {
    throw FormatException('Battery level is outside 0..100: $level');
  }
  if (source != 0 && source != 1) {
    throw FormatException('Unknown battery power source: $source');
  }
  return CameraBattery(level: level, acPowered: source == 1);
}

Uint8List encodeOperationRequest({
  required bool start,
  required bool autoFocus,
}) =>
    Uint8List.fromList([start ? 1 : 2, autoFocus ? 1 : 0]);

Uint8List encodeCameraPower(int value) {
  if (value < 0 || value > 2) {
    throw RangeError.range(value, 0, 2, 'value');
  }
  return Uint8List.fromList([value]);
}

Uint8List encodeNetworkType(int value) {
  if (value < 0 || value > 1) {
    throw RangeError.range(value, 0, 1, 'value');
  }
  return Uint8List.fromList([value]);
}
