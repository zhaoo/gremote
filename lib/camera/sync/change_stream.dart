import 'dart:async';
import 'dart:convert';

import '../gateway/change_socket.dart';
import '../protocol/protocol_profile.dart';
import 'camera_state.dart';

typedef PropsCallback = void Function(Map<String, Object?> json,
    {required bool full});

/// Keeps camera state fresh: `/v1/changes` WebSocket first, 1 s polling of
/// `/v1/props` while the socket is down (firmware-derived / unverified).
class ChangeStream {
  ChangeStream({
    required ChangeSocket socket,
    required Future<Map<String, Object?>> Function() fetchProps,
    required PropsCallback onProps,
    required void Function(SyncMode) onMode,
    required void Function(WsSupport) onSupport,
    required WsSupport initialSupport,
    this.pollInterval = const Duration(seconds: 1),
  })  : _socket = socket,
        _fetchProps = fetchProps,
        _onProps = onProps,
        _onMode = onMode,
        _onSupport = onSupport,
        _support = initialSupport;

  static const path = '/v1/changes';
  static const _backoffSeconds = [1, 2, 4, 8, 16, 30];
  static const _maxHandshakeFailures = 3;

  final ChangeSocket _socket;
  final Future<Map<String, Object?>> Function() _fetchProps;
  final PropsCallback _onProps;
  final void Function(SyncMode) _onMode;
  final void Function(WsSupport) _onSupport;
  final Duration pollInterval;

  WsSupport _support;
  StreamSubscription<ChangeSocketEvent>? _subscription;
  Timer? _reconnect;
  Timer? _poll;
  var _running = false;
  var _pollingAllowed = false;
  var _everOpened = false;
  var _handshakeFailures = 0;
  var _attempt = 0;
  var _refreshing = false;
  var _mode = SyncMode.offline;

  SyncMode get mode => _mode;

  Future<void> start() async {
    _running = true;
    _subscription = _socket.events.listen(_onEvent);
    _setMode(SyncMode.polling);
    if (_support == WsSupport.unsupported) {
      _updatePolling();
    } else {
      _open();
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _reconnect?.cancel();
    _poll?.cancel();
    _poll = null;
    _setMode(SyncMode.offline);
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _socket.close();
    } on Exception {
      // Transport already gone.
    }
  }

  /// Polling only runs while the shoot page is visible and in foreground.
  void setPollingAllowed(bool allowed) {
    _pollingAllowed = allowed;
    _updatePolling();
  }

  Future<void> refresh() async => _onProps(await _fetchProps(), full: true);

  void _open() {
    unawaited(_socket.open(path).catchError((Object _) {
      _onEvent(const ChangeSocketFailed(null));
    }));
  }

  void _onEvent(ChangeSocketEvent event) {
    if (!_running) return;
    switch (event) {
      case ChangeSocketOpened():
        _everOpened = true;
        _handshakeFailures = 0;
        _attempt = 0;
        if (_support != WsSupport.supported) {
          _support = WsSupport.supported;
          _onSupport(_support);
        }
        _setMode(SyncMode.webSocket);
        _updatePolling();
        unawaited(_quietRefresh());
      case ChangeSocketMessage(:final text):
        final json = _decode(text);
        if (json != null) _onProps(json, full: false);
      case ChangeSocketClosed() || ChangeSocketFailed():
        _onDown();
    }
  }

  void _onDown() {
    _setMode(SyncMode.polling);
    if (!_everOpened && ++_handshakeFailures >= _maxHandshakeFailures) {
      _support = WsSupport.unsupported;
      _onSupport(_support);
    } else {
      final delay =
          _backoffSeconds[_attempt.clamp(0, _backoffSeconds.length - 1)];
      _attempt++;
      _reconnect?.cancel();
      _reconnect = Timer(Duration(seconds: delay), () {
        if (_running) _open();
      });
    }
    _updatePolling();
  }

  void _updatePolling() {
    final shouldPoll = _running && _mode == SyncMode.polling && _pollingAllowed;
    if (shouldPoll && _poll == null) {
      _poll = Timer.periodic(pollInterval, (_) => unawaited(_quietRefresh()));
    } else if (!shouldPoll) {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _quietRefresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await refresh();
    } on Exception {
      // The controller records props failures.
    } finally {
      _refreshing = false;
    }
  }

  void _setMode(SyncMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _onMode(mode);
  }

  static Map<String, Object?>? _decode(String text) {
    try {
      final value = jsonDecode(text);
      return value is Map<String, Object?> ? value : null;
    } on FormatException {
      return null;
    }
  }
}
