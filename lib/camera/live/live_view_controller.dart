import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/connection_controller.dart';
import '../connection/connection_state.dart';
import '../gateway/camera_transport.dart';
import '../http/live_view_parser.dart';

final liveViewControllerProvider =
    NotifierProvider<LiveViewController, Uint8List?>(LiveViewController.new);

/// Reference-counted Live View owner. Shoot UI and metering may attach
/// independently; the native stream is stopped only after the final detach.
class LiveViewController extends Notifier<Uint8List?> {
  late CameraTransport _transport;
  final _parser = LiveViewParser();
  StreamSubscription<Uint8List>? _chunks;
  var _references = 0;
  var _started = false;
  var _syncing = false;
  var _dirty = false;
  String? _error;

  String? get error => _error;
  int get references => _references;

  @override
  Uint8List? build() {
    _transport = ref.watch(cameraGatewaysProvider).transport;
    _chunks = _transport.liveViewChunks.listen(_onChunk);
    ref.listen(connectionControllerProvider, (_, __) => unawaited(_sync()));
    ref.onDispose(() {
      unawaited(_chunks?.cancel());
      if (_started) unawaited(_transport.stopLiveView());
    });
    return null;
  }

  void attach() {
    _references++;
    unawaited(_sync());
  }

  void detach() {
    if (_references == 0) return;
    _references--;
    unawaited(_sync());
  }

  /// Serialises native start/stop; triggers arriving mid-flight re-run once.
  Future<void> _sync() async {
    if (_syncing) {
      _dirty = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _dirty = false;
        await _apply();
      } while (_dirty);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _apply() async {
    final ready = ref.read(connectionControllerProvider) is ConnectionReady;
    final shouldRun = ready && _references > 0;
    if (shouldRun && !_started) {
      _started = true;
      _parser.reset();
      _error = null;
      try {
        await _transport.startLiveView('/v1/liveview');
      } on Exception {
        _started = false;
        _error = '实时取景启动失败';
      }
    } else if (!shouldRun && _started) {
      _started = false;
      await _transport.stopLiveView();
      _parser.reset();
      state = null;
    }
  }

  void _onChunk(Uint8List chunk) {
    final frames = _parser.add(chunk);
    if (frames.isNotEmpty) {
      _error = null;
      state = frames.last;
    }
  }
}
