import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_presence.dart';
import '../../diagnostics/diagnostic_event.dart';
import '../../diagnostics/diagnostic_store.dart';
import '../capture/capture_tracker.dart';
import '../connection/connection_controller.dart';
import '../connection/connection_state.dart';
import '../gateway/native_gateways.dart';
import '../http/camera_api.dart';
import '../http/camera_files.dart';
import '../params/camera_param.dart';
import '../params/param_writer.dart';
import '../protocol/props_parser.dart';
import '../protocol/protocol_profile.dart';
import 'camera_state.dart';
import 'change_stream.dart';

final cameraStateControllerProvider =
    NotifierProvider<CameraStateController, CameraState>(
  CameraStateController.new,
);

/// Shots seen this session, newest last.
final latestCaptureProvider = StreamProvider<CaptureRecord>(
    (ref) => ref.watch(cameraStateControllerProvider.notifier).captures);

class SettingsRestoreReport {
  const SettingsRestoreReport(
      {this.restored = const [], this.failed = const {}});
  final List<String> restored;
  final Map<String, String> failed;
  bool get success => failed.isEmpty;
}

class _Session {
  _Session({
    required this.firmware,
    required this.profile,
    required this.writer,
    required this.stream,
    required this.tracker,
  });

  Map<String, CameraParam>? baseline;
  final String firmware;
  ProtocolProfile profile;
  final ParamWriter writer;
  final ChangeStream stream;
  final CaptureTracker tracker;
  StreamSubscription<CaptureRecord>? records;
}

/// The single source of camera parameter/status truth while connected.
class CameraStateController extends Notifier<CameraState> {
  static const _propsFailureThreshold = 5;

  late CameraApi _api;
  late CameraGatewayBundle _bundle;
  _Session? _session;
  Object? _starting;
  final _captures = StreamController<CaptureRecord>.broadcast();
  var _propsFailures = 0;
  var _shooting = 0;
  Future<SettingsRestoreReport>? _restoring;

  CameraApi get api => _api;
  Stream<CaptureRecord> get captures => _captures.stream;
  ProtocolProfile? get profile => _session?.profile;

  @override
  CameraState build() {
    _bundle = ref.watch(cameraGatewaysProvider);
    _api = CameraApi(_bundle.transport);
    ref.listen(connectionControllerProvider, (_, next) => _onConnection(next));
    ref.listen(appForegroundProvider, (_, foreground) {
      _updatePolling();
      if (foreground) unawaited(_quietRefresh());
    });
    ref.listen(shootPageVisibleProvider, (_, __) => _updatePolling());
    ref.onDispose(() {
      _starting = null;
      unawaited(_endSession());
      unawaited(_captures.close());
    });
    final current = ref.read(connectionControllerProvider);
    if (current is ConnectionReady) {
      scheduleMicrotask(() => _onConnection(current));
    }
    return CameraState.offline;
  }

  /// Writes one parameter; the camera's readback decides the outcome.
  Future<WriteOutcome> setParam(String wireKey, String value) async {
    if (_restoring != null) return const WriteRejected('restoring');
    final session = _session;
    final param = state.params[wireKey];
    if (session == null || param == null) return const WriteRejected('offline');
    if (session.baseline == null) return const WriteRejected('noBaseline');
    if (!state.writesEnabled) return const WritesDisabled();
    if (!param.writable) return const WriteRejected('notWritable');
    state = state.copyWith(pending: {...state.pending, wireKey: value});
    final outcome = await session.writer.write(param, value);
    if (_session == session && state.pending[wireKey] == value) {
      state = state.copyWith(pending: {...state.pending}..remove(wireKey));
    }
    return outcome;
  }

  /// Restores the first camera readback for this connection. No protocol values
  /// are synthesized; changed settings must still advertise the original value.
  Future<SettingsRestoreReport> restoreConnectionSettings() {
    final pending = _restoring;
    if (pending != null) return pending;
    final operation = _restoreConnectionSettings();
    _restoring = operation;
    return operation.whenComplete(() {
      if (identical(_restoring, operation)) _restoring = null;
    });
  }

  Future<SettingsRestoreReport> _restoreConnectionSettings() async {
    final session = _session;
    if (session == null) {
      return const SettingsRestoreReport(failed: {'connection': 'offline'});
    }
    await session.writer.drain();
    if (_session != session) {
      return const SettingsRestoreReport(failed: {'connection': 'offline'});
    }
    try {
      await session.stream.refresh();
    } on Exception {
      return const SettingsRestoreReport(failed: {'connection': 'readFailed'});
    }
    final baseline = session.baseline;
    if (baseline == null) {
      return const SettingsRestoreReport(failed: {'connection': 'noBaseline'});
    }
    final restored = <String>[];
    final failed = <String, String>{};
    for (final original in baseline.values) {
      if (!original.writable || original.current == null) continue;
      final key = original.wireKey;
      if (_session != session) {
        failed[key] = 'offline';
        continue;
      }
      final current = state.params[key];
      if (current?.current == original.current) continue;
      if (current == null ||
          !current.writable ||
          !current.options.contains(original.current)) {
        failed[key] = 'unsupported';
        continue;
      }
      if (!state.writesEnabled) {
        failed[key] = 'writesDisabled';
        continue;
      }
      final outcome = await session.writer.write(current, original.current!);
      // A timeout completes the UI future before the underlying write settles.
      await session.writer.drain();
      if (_session != session) {
        failed[key] = 'offline';
        continue;
      }
      try {
        await session.stream.refresh();
        if (_session == session &&
            state.params[key]?.current == original.current) {
          restored.add(key);
        } else {
          failed[key] = 'readbackMismatch';
        }
      } on Exception {
        failed[key] = 'readFailed';
      }
      if (outcome is WritesDisabled) failed[key] = 'writesDisabled';
    }
    return SettingsRestoreReport(restored: restored, failed: failed);
  }

  /// HTTP shutter, then waits for the new file(s).
  Future<List<CaptureRecord>> shootAndAwait({
    required bool autoFocus,
    required CaptureContext context,
  }) async {
    final session = _requireSession();
    _shooting++;
    try {
      await session.tracker.ensurePrimed();
      await _api.shoot(autoFocus: autoFocus);
      return await session.tracker.detect(context, timeout: _captureTimeout);
    } finally {
      _shooting--;
    }
  }

  /// Picks up a shot fired by the app over BLE.
  Future<List<CaptureRecord>> trackAppShot() async {
    final session = _session;
    if (session == null) return const [];
    _shooting++;
    try {
      return await session.tracker.detect(
        CaptureContext(
            source: CaptureSource.app, effect: state.value(ParamKey.effect)),
        timeout: _captureTimeout,
      );
    } finally {
      _shooting--;
    }
  }

  Future<void> refresh() async => _session?.stream.refresh();

  Future<void> saveProfile(ProtocolProfile profile) async {
    final session = _session;
    if (session != null && session.firmware == profile.firmware) {
      session.profile = profile;
    }
    await ref.read(protocolProfileStoreProvider).save(profile);
  }

  Duration get _captureTimeout =>
      CaptureTracker.timeoutFor(state.value(ParamKey.shutter));

  _Session _requireSession() =>
      _session ?? (throw StateError('camera not connected'));

  void _onConnection(CameraConnectionState next) {
    if (next is ConnectionReady) {
      if (_session == null && _starting == null) {
        unawaited(_startSession(next.snapshot.identity.firmware));
      }
    } else {
      _starting = null;
      if (_session != null) unawaited(_endSession());
    }
  }

  Future<void> _startSession(String firmware) async {
    final token = _starting = Object();
    _propsFailures = 0;
    state = const CameraState(syncMode: SyncMode.polling);
    final profile = await ref.read(protocolProfileStoreProvider).load(firmware);
    if (_starting != token) return;
    _starting = null;

    late final _Session session;
    session = _Session(
      firmware: firmware,
      profile: profile,
      writer: ParamWriter(
        send: _api.putParams,
        refreshAndRead: (key) async {
          await session.stream.refresh();
          return state.params[key]?.current;
        },
        encoding: () => session.profile.writeEncoding,
        rememberEncoding: (encoding) =>
            saveProfile(session.profile.copyWith(writeEncoding: encoding)),
        disableWrites: () {
          if (_session == session) {
            state = state.copyWith(writesEnabled: false);
          }
          _diagnose('params', 'writesUnsupported');
        },
      ),
      stream: ChangeStream(
        socket: _bundle.changes,
        fetchProps: _fetchProps,
        onProps: (json, {required full}) {
          if (_session == session) _applyProps(json, full: full);
        },
        onMode: (mode) {
          if (_session == session) state = state.copyWith(syncMode: mode);
        },
        onSupport: (support) => unawaited(
            saveProfile(session.profile.copyWith(webSocket: support))),
        initialSupport: profile.webSocket,
      ),
      tracker: CaptureTracker(
        listPhotos: _api.photos,
        captureWallSeconds: (file) async =>
            parseCaptureWallSeconds(await _api.photoInfo(file)),
      ),
    );
    _session = session;
    session.records = session.tracker.records.listen(_captures.add);

    await _quietRefresh();
    try {
      await session.tracker.prime();
    } on Exception {
      // Retried before the first shot.
    }
    if (_session != session) return;
    await session.stream.start();
    _updatePolling();
  }

  Future<void> _endSession() async {
    final session = _session;
    if (session == null) return;
    _session = null;
    state = CameraState.offline;
    await session.records?.cancel();
    session.tracker.dispose();
    await session.stream.stop();
  }

  Future<Map<String, Object?>> _fetchProps() async {
    try {
      final json = await _api.props();
      _propsFailures = 0;
      return json;
    } on Exception {
      if (++_propsFailures == _propsFailureThreshold) {
        _diagnose('props', 'propsUnavailable');
      }
      rethrow;
    }
  }

  Future<void> _quietRefresh() async {
    try {
      await refresh();
    } on Exception {
      // Counted by _fetchProps.
    }
  }

  void _applyProps(Map<String, Object?> json, {required bool full}) {
    final parsed = parseProps(json);
    final before = state.status;
    state = state.applyProps(parsed);
    if (full) _session?.baseline ??= Map.unmodifiable(state.params);
    final after = state.status;
    final newCaptureId = parsed.status.captureId != null &&
        before.captureId != null &&
        parsed.status.captureId != before.captureId;
    final remainDropped = before.remain != null &&
        after.remain != null &&
        after.remain! < before.remain!;
    if ((newCaptureId || remainDropped) && _shooting == 0) {
      final session = _session;
      unawaited(session?.tracker
          .detect(
            CaptureContext(
                source: CaptureSource.body,
                effect: state.value(ParamKey.effect)),
            timeout: const Duration(seconds: 3),
          )
          .catchError((Object _) => const <CaptureRecord>[]));
    }
  }

  void _updatePolling() => _session?.stream.setPollingAllowed(
      ref.read(appForegroundProvider) && ref.read(shootPageVisibleProvider));

  void _diagnose(String stage, String code) {
    ref.read(diagnosticStoreProvider).record(DiagnosticEvent(
          stage: stage,
          monotonicMicros: DateTime.now().microsecondsSinceEpoch,
          durationMs: 0,
          retryCount: 0,
          firmware: _session?.firmware,
          exceptionCode: code,
        ));
  }
}
