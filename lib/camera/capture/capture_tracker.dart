import 'dart:async';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../http/camera_files.dart';
import '../params/exposure_values.dart';

enum CaptureSource { app, body, program }

enum TimeSource { camera, phone }

/// One shot (RAW+JPEG pairs share a record).
@immutable
class CaptureRecord {
  const CaptureRecord({
    required this.dir,
    required this.baseName,
    required this.files,
    required this.wallSeconds,
    required this.timeSource,
    required this.source,
    this.effect,
    this.programRunId,
    this.recipeId,
    this.filmRollId,
    this.filmRecipeJson,
  });

  final String dir;
  final String baseName;
  final List<String> files;

  /// Wall-clock seconds (see `wallSecondsOf`).
  final int wallSeconds;
  final TimeSource timeSource;
  final CaptureSource source;

  /// Camera `effect` when the shot was taken.
  final String? effect;
  final String? programRunId;

  /// Set by recipe brackets; overrides the active session recipe.
  final String? recipeId;
  final String? filmRollId, filmRecipeJson;

  CameraFile get primaryFile => CameraFile(dir: dir, file: files.first);
}

@immutable
class CaptureContext {
  const CaptureContext({
    required this.source,
    this.effect,
    this.programRunId,
    this.recipeId,
    this.filmRollId,
    this.filmRecipeJson,
  });

  final CaptureSource source;
  final String? effect;
  final String? programRunId;
  final String? recipeId;
  final String? filmRollId, filmRecipeJson;
}

class CaptureFileUpdate {
  const CaptureFileUpdate(
      {required this.dir, required this.baseName, required this.files});
  final String dir, baseName;
  final List<String> files;
}

/// Finds new shots by diffing `/v1/photos` (firmware-derived / unverified).
class CaptureTracker {
  CaptureTracker({
    required Future<List<CameraFile>> Function() listPhotos,
    required Future<int?> Function(CameraFile) captureWallSeconds,
    int Function()? phoneSeconds,
    this.poll = const Duration(seconds: 1),
  })  : _listPhotos = listPhotos,
        _captureWallSeconds = captureWallSeconds,
        _phoneSeconds = phoneSeconds ?? phoneWallSeconds;

  final Future<List<CameraFile>> Function() _listPhotos;
  final Future<int?> Function(CameraFile) _captureWallSeconds;
  final int Function() _phoneSeconds;
  final Duration poll;

  final _known = <CameraFile>{};
  final _recorded = <String>{};
  final _records = StreamController<CaptureRecord>.broadcast();
  final _fileUpdates = StreamController<CaptureFileUpdate>.broadcast();
  var _primed = false;
  bool _disposed = false;
  Future<List<CaptureRecord>>? _inFlight;
  CaptureContext? _context;

  Stream<CaptureRecord> get records => _records.stream;
  Stream<CaptureFileUpdate> get fileUpdates => _fileUpdates.stream;

  static Duration timeoutFor(String? tv) {
    final seconds = tv == null ? null : parseTvSeconds(tv);
    final ms = seconds == null ? 0 : (seconds * 2000).round() + 5000;
    return Duration(milliseconds: math.max(10000, ms));
  }

  /// Records the current file list as the baseline.
  Future<void> prime() async {
    final files = await _listPhotos();
    if (_disposed) return;
    _known
      ..clear()
      ..addAll(files);
    _recorded
      ..clear()
      ..addAll(files.map((f) => '${f.dir}/${f.baseName}'));
    _primed = true;
  }

  Future<void> ensurePrimed() async {
    if (!_primed) await prime();
  }

  /// Waits until new files appear or [timeout] passes (empty list).
  ///
  /// Concurrent calls share one diff; an app/program context replaces a
  /// body context.
  Future<List<CaptureRecord>> detect(
    CaptureContext context, {
    required Duration timeout,
  }) {
    if (_disposed) return Future.value(const []);
    final active = _inFlight;
    if (active != null) {
      if (context.source != CaptureSource.body) _context = context;
      return active;
    }
    _context = context;
    final future = _detect(timeout).whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_records.close());
    unawaited(_fileUpdates.close());
  }

  Future<List<CaptureRecord>> _detect(Duration timeout) async {
    if (!_primed) {
      // Without a baseline every file would look new.
      try {
        await prime();
      } on Exception {
        // Retried on the next detect.
      }
      return const [];
    }
    var waited = Duration.zero;
    while (true) {
      if (_disposed) return const [];
      final fresh = await _freshFiles();
      if (fresh.isNotEmpty) return _build(fresh);
      if (waited >= timeout) return const [];
      await Future<void>.delayed(poll);
      waited += poll;
    }
  }

  Future<List<CameraFile>> _freshFiles() async {
    try {
      final files = await _listPhotos();
      if (_disposed) return const [];
      final fresh = files.where((f) => !_known.contains(f)).toList();
      _known.addAll(fresh);
      return fresh;
    } on Exception {
      return const [];
    }
  }

  Future<List<CaptureRecord>> _build(List<CameraFile> fresh) async {
    final groups = <String, List<CameraFile>>{};
    for (final file in fresh) {
      final key = '${file.dir}/${file.baseName}';
      // A late RAW of an already-recorded JPEG is not a new shot.
      if (_recorded.contains(key)) {
        _fileUpdates.add(CaptureFileUpdate(
            dir: file.dir, baseName: file.baseName, files: [file.file]));
        continue;
      }
      groups.putIfAbsent(key, () => []).add(file);
    }
    final context = _context!;
    final records = <CaptureRecord>[];
    for (final files in groups.values) {
      final first = files.first;
      int? cameraSeconds;
      try {
        cameraSeconds = await _captureWallSeconds(first);
      } on Exception {
        cameraSeconds = null;
      }
      if (_disposed) break;
      final record = CaptureRecord(
        dir: first.dir,
        baseName: first.baseName,
        files: List.unmodifiable([for (final f in files) f.file]),
        wallSeconds: cameraSeconds ?? _phoneSeconds(),
        timeSource:
            cameraSeconds == null ? TimeSource.phone : TimeSource.camera,
        source: context.source,
        effect: context.effect,
        programRunId: context.programRunId,
        recipeId: context.recipeId,
        filmRollId: context.filmRollId,
        filmRecipeJson: context.filmRecipeJson,
      );
      _recorded.add('${first.dir}/${first.baseName}');
      records.add(record);
      _records.add(record);
    }
    return records;
  }
}
