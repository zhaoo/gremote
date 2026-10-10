import 'dart:convert';

import 'ble_gateway.dart';

/// `/v1/changes` WebSocket events (firmware-derived / hardware-unverified).
sealed class ChangeSocketEvent {
  const ChangeSocketEvent();
}

class ChangeSocketOpened extends ChangeSocketEvent {
  const ChangeSocketOpened();
}

class ChangeSocketMessage extends ChangeSocketEvent {
  const ChangeSocketMessage(this.text);
  final String text;
}

class ChangeSocketClosed extends ChangeSocketEvent {
  const ChangeSocketClosed(this.code);
  final int? code;
}

/// Handshake or transport failure; [status] is the HTTP status if any.
class ChangeSocketFailed extends ChangeSocketEvent {
  const ChangeSocketFailed(this.status);
  final int? status;
}

abstract interface class ChangeSocket {
  Stream<ChangeSocketEvent> get events;

  /// [path] is relative, like every other camera request.
  Future<void> open(String path);

  Future<void> close();
}

abstract interface class DeviceScreen {
  Future<void> setKeepScreenOn(bool on);
}

/// Maps a native `changes.*` event; other event types return null.
ChangeSocketEvent? changeSocketEventFrom(CameraDeviceEvent event) {
  final payload = _object(event.jsonPayload);
  return switch (event.type) {
    'changes.open' => const ChangeSocketOpened(),
    'changes.message' => switch (payload?['text']) {
        final String text => ChangeSocketMessage(text),
        _ => null,
      },
    'changes.closed' => ChangeSocketClosed(_int(payload?['code'])),
    'changes.failure' => ChangeSocketFailed(_int(payload?['status'])),
    _ => null,
  };
}

int? _int(Object? value) => value is num ? value.toInt() : null;

Map<String, Object?>? _object(String source) {
  try {
    final value = jsonDecode(source);
    return value is Map<String, Object?> ? value : null;
  } on FormatException {
    return null;
  }
}
