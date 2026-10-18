import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import '../app/app_presence.dart';
import '../camera/capture/capture_tracker.dart';
import '../camera/connection/connection_controller.dart';
import '../camera/connection/connection_state.dart';
import '../camera/sync/camera_state_controller.dart';
import '../darkroom/darkroom_providers.dart';

class LocationFix {
  const LocationFix(
      {required this.latitude,
      required this.longitude,
      required this.accuracy,
      required this.timestamp,
      this.altitude});
  final double latitude, longitude, accuracy;
  final double? altitude;
  final DateTime timestamp;
  bool usableAt(DateTime now) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180 &&
      accuracy.isFinite &&
      accuracy >= 0 &&
      accuracy <= 100 &&
      now.difference(timestamp).inMilliseconds >= -5000 &&
      now.difference(timestamp).inSeconds <= 45;
}

abstract interface class LocationGateway {
  Stream<LocationFix> get fixes;
  Future<bool> requestPermission();
  Future<void> start();
  Future<void> stop();
}

class NativeLocationGateway implements LocationGateway {
  static const _channel = MethodChannel('gremote/location');
  static const _events = EventChannel('gremote/location/fixes');
  @override
  Future<bool> requestPermission() async =>
      (await Permission.locationWhenInUse.request()).isGranted;
  @override
  Stream<LocationFix> get fixes => _events
          .receiveBroadcastStream()
          .where((value) => value is Map)
          .map((value) {
        final map = value as Map;
        return LocationFix(
            latitude: (map['latitude'] as num).toDouble(),
            longitude: (map['longitude'] as num).toDouble(),
            accuracy: (map['accuracy'] as num).toDouble(),
            timestamp:
                DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
            altitude: (map['altitude'] as num?)?.toDouble());
      });
  @override
  Future<void> start() => _channel.invokeMethod<void>('start');
  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

class SavedShotLocation {
  const SavedShotLocation(this.dir, this.baseName, this.capturedAt, this.fix);
  final String dir, baseName;
  final DateTime capturedAt;
  final LocationFix fix;
}

class ShotLocationStore {
  ShotLocationStore(this.db);
  final Database db;
  Future<void> save(CaptureRecord shot, LocationFix fix, DateTime now) async {
    await db.insert(
        'shot_locations',
        {
          'dir': shot.dir,
          'base_name': shot.baseName,
          'capture_wall_seconds': shot.wallSeconds,
          'recorded_at': now.millisecondsSinceEpoch,
          'latitude': fix.latitude,
          'longitude': fix.longitude,
          'accuracy': fix.accuracy,
          'altitude': fix.altitude,
          'measured_at': fix.timestamp.millisecondsSinceEpoch
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SavedShotLocation>> recent() async {
    final rows = await db.query('shot_locations',
        orderBy: 'recorded_at DESC', limit: 100);
    return rows
        .map((row) => SavedShotLocation(
            row['dir'] as String,
            row['base_name'] as String,
            DateTime.fromMillisecondsSinceEpoch(row['recorded_at'] as int),
            LocationFix(
                latitude: (row['latitude'] as num).toDouble(),
                longitude: (row['longitude'] as num).toDouble(),
                accuracy: (row['accuracy'] as num).toDouble(),
                altitude: (row['altitude'] as num?)?.toDouble(),
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                    row['measured_at'] as int))))
        .toList();
  }
}

class LocationRecordingState {
  const LocationRecordingState(
      {this.enabled = false, this.active = false, this.fix, this.error});
  final bool enabled, active;
  final LocationFix? fix;
  final String? error;
}

final locationGatewayProvider =
    Provider<LocationGateway>((_) => NativeLocationGateway());
final locationClockProvider =
    Provider<DateTime Function()>((_) => DateTime.now);
final shotLocationStoreProvider =
    Provider((ref) => ShotLocationStore(ref.read(databaseProvider)));
final shotLocationsProvider =
    FutureProvider((ref) => ref.read(shotLocationStoreProvider).recent());
final locationRecordingProvider =
    NotifierProvider<LocationRecordingController, LocationRecordingState>(
        LocationRecordingController.new);

class LocationRecordingController extends Notifier<LocationRecordingState> {
  late final LocationGateway _gateway;
  late final Future<void> ready;
  StreamSubscription<LocationFix>? _subscription;
  StreamSubscription<CaptureRecord>? _captures;
  AppLifecycleListener? _lifecycle;
  Future<void> _pending = Future.value();
  bool _foreground = true, _disposed = false;
  int _epoch = 0;
  @override
  LocationRecordingState build() {
    _gateway = ref.read(locationGatewayProvider);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    ref.listen(shootPageVisibleProvider, (_, __) => unawaited(sync()));
    ref.listen(connectionControllerProvider, (_, __) => unawaited(sync()));
    _captures = ref
        .read(cameraStateControllerProvider.notifier)
        .captures
        .listen((shot) => unawaited(record(shot)));
    _lifecycle = AppLifecycleListener(
        onStateChange: (next) =>
            unawaited(setForeground(next == AppLifecycleState.resumed)));
    ref.onDispose(() {
      _disposed = true;
      _epoch++;
      _lifecycle?.dispose();
      unawaited(_subscription?.cancel());
      unawaited(_captures?.cancel());
      unawaited(_gateway.stop().catchError((Object _) {}));
    });
    ready = Future.microtask(_load);
    return const LocationRecordingState();
  }

  Future<void> _load() async {
    final rows = await ref
        .read(databaseProvider)
        .query('app_kv', where: 'key = ?', whereArgs: ['record_location']);
    if (_disposed) return;
    state = LocationRecordingState(
        enabled: rows.isNotEmpty && rows.first['value'] == 'true');
    await sync();
  }

  Future<void> setEnabled(bool enabled) async {
    await ready;
    if (_disposed) return;
    if (enabled && !await _gateway.requestPermission()) {
      if (!_disposed) {
        await ref.read(databaseProvider).insert(
            'app_kv', {'key': 'record_location', 'value': 'false'},
            conflictAlgorithm: ConflictAlgorithm.replace);
        if (!_disposed) {
          state = LocationRecordingState(active: state.active);
          await sync();
          if (!_disposed) {
            state = const LocationRecordingState(error: '未获得定位权限，可在系统设置中授权');
          }
        }
      }
      return;
    }
    if (_disposed) return;
    await ref.read(databaseProvider).insert(
        'app_kv', {'key': 'record_location', 'value': '$enabled'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (_disposed) return;
    state = LocationRecordingState(
        enabled: enabled, active: state.active, fix: state.fix);
    await sync();
  }

  Future<void> setForeground(bool foreground) {
    _foreground = foreground;
    return sync();
  }

  Future<void> sync() {
    _pending = _pending.then((_) => _sync());
    return _pending;
  }

  Future<void> _sync() async {
    if (_disposed) return;
    final run = state.enabled &&
        _foreground &&
        ref.read(shootPageVisibleProvider) &&
        ref.read(connectionControllerProvider) is ConnectionReady;
    if (run && state.active) return;
    if (!run && !state.active && _subscription == null) return;
    if (!run) {
      _epoch++;
      state = LocationRecordingState(enabled: state.enabled);
      await _subscription?.cancel();
      _subscription = null;
      try {
        await _gateway.stop();
      } catch (_) {/* Native lifecycle also stops location. */}
      return;
    }
    final epoch = ++_epoch;
    try {
      _subscription = _gateway.fixes.listen((fix) {
        if (_disposed ||
            epoch != _epoch ||
            !state.active ||
            !fix.usableAt(ref.read(locationClockProvider)())) {
          return;
        }
        state = LocationRecordingState(
            enabled: state.enabled, active: true, fix: fix);
      }, onError: (Object _) {
        if (_disposed || epoch != _epoch) return;
        _epoch++;
        final subscription = _subscription;
        _subscription = null;
        unawaited(subscription?.cancel());
        state = LocationRecordingState(
            enabled: state.enabled, error: '定位不可用，请检查手机定位开关后重新开启');
        unawaited(_gateway.stop().catchError((Object _) {}));
      });
      await _gateway.start();
      if (_disposed || epoch != _epoch) {
        await _gateway.stop();
        return;
      }
      state = LocationRecordingState(enabled: state.enabled, active: true);
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      if (!_disposed) {
        state = LocationRecordingState(
            enabled: state.enabled, error: '定位不可用，请检查手机定位开关后重新开启');
      }
    }
  }

  Future<void> record(CaptureRecord shot) async {
    if (_disposed ||
        !state.active ||
        !state.enabled ||
        !_foreground ||
        !ref.read(shootPageVisibleProvider) ||
        ref.read(connectionControllerProvider) is! ConnectionReady) return;
    final now = ref.read(locationClockProvider)();
    final fix = state.fix;
    if (fix == null || !fix.usableAt(now)) return;
    try {
      await ref.read(shotLocationStoreProvider).save(shot, fix, now);
      if (!_disposed) ref.invalidate(shotLocationsProvider);
    } catch (_) {
      if (!_disposed) {
        state = LocationRecordingState(
            enabled: state.enabled,
            active: state.active,
            fix: state.fix,
            error: '拍摄位置未能保存，请检查手机存储空间');
      }
    }
  }
}
