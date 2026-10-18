import 'dart:async';

import 'package:meta/meta.dart';

import '../capture/capture_tracker.dart';
import '../params/camera_param.dart';
import '../params/param_writer.dart';
import 'program.dart';

enum RunPhase { idle, preparing, refused, running, paused, completed, aborted }

@immutable
class ProgramRunState {
  const ProgramRunState({
    this.phase = RunPhase.idle,
    this.kind,
    this.done = 0,
    this.total = 0,
    this.nextAt,
    this.reason,
    this.nudgeEv = 0,
    this.runId,
  });

  final RunPhase phase;
  final String? kind;
  final int done;
  final int total;
  final DateTime? nextAt;
  final String? reason;
  final double nudgeEv;
  final String? runId;

  ProgramRunState copyWith({
    RunPhase? phase,
    String? kind,
    int? done,
    int? total,
    DateTime? nextAt,
    bool clearNextAt = false,
    String? reason,
    bool clearReason = false,
    double? nudgeEv,
    String? runId,
  }) =>
      ProgramRunState(
        phase: phase ?? this.phase,
        kind: kind ?? this.kind,
        done: done ?? this.done,
        total: total ?? this.total,
        nextAt: clearNextAt ? null : nextAt ?? this.nextAt,
        reason: clearReason ? null : reason ?? this.reason,
        nudgeEv: nudgeEv ?? this.nudgeEv,
        runId: runId ?? this.runId,
      );
}

/// Executes programs on Dart's event loop. A camera failure retries once,
/// then pauses on the same frame until the user explicitly resumes.
class ProgramRunner {
  ProgramRunner({
    required ProgramCamera camera,
    required void Function(ProgramRunState) onState,
    DateTime Function()? now,
    String Function()? newId,
  })  : _camera = camera,
        _onState = onState,
        _now = now ?? DateTime.now,
        _newId = newId ??
            (() =>
                'run-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}');

  final ProgramCamera _camera;
  final void Function(ProgramRunState) _onState;
  final DateTime Function() _now;
  final String Function() _newId;

  ProgramRunState _state = const ProgramRunState();
  Program? _program;
  DateTime? _startAt;
  Map<String, String> _snapshot = const {};
  final _touched = <String>{};
  final List<Map<String, Object?>> _log = [];
  var _index = 0;
  var _generation = 0;
  var _runningLoop = false;
  Future<void>? _activeOperation;
  Future<void>? _abortOperation;
  Timer? _timer;
  Completer<void>? _wake;

  ProgramRunState get state => _state;
  List<Map<String, Object?>> get log => List.unmodifiable(_log);

  Future<void> start(Program program, {bool autoFocusFirst = false}) {
    if (_activeOperation != null ||
        _abortOperation != null ||
        _state.phase == RunPhase.paused) {
      throw StateError('a program is already active');
    }
    return _track(() => _start(program, autoFocusFirst: autoFocusFirst));
  }

  Future<void> _track(Future<void> Function() operation) {
    final settled = Completer<void>();
    _activeOperation = settled.future;
    return (() async {
      try {
        await operation();
      } finally {
        _activeOperation = null;
        settled.complete();
      }
    })();
  }

  Future<void> _start(Program program, {required bool autoFocusFirst}) async {
    final generation = _generation;
    final refusal = program.refusal(_camera.state);
    final runId = _newId();
    _set(ProgramRunState(
      phase: RunPhase.preparing,
      kind: program.kind,
      total: program.frameCount,
      runId: runId,
    ));
    if (refusal != null) {
      _set(_state.copyWith(phase: RunPhase.refused, reason: refusal));
      return;
    }
    _program = program;
    _snapshot = {
      for (final param in _camera.state.params.values)
        if (param.current != null) param.wireKey: param.current!,
    };
    _touched.clear();
    _log.clear();
    _index = 0;
    _startAt = _now();
    final drive = _camera.state.param(ParamKey.drive);
    if (drive?.writable == true && drive!.current != 'single') {
      final written = await _write('shootMode', 'single');
      if (generation != _generation) return;
      if (!written) {
        _set(_state.copyWith(phase: RunPhase.refused, reason: '无法切换到单张模式'));
        return;
      }
    }
    if (generation != _generation) return;
    await _run(autoFocusFirst: autoFocusFirst);
  }

  void pause(String reason) {
    if (_state.phase != RunPhase.running) return;
    _generation++;
    _interruptDelay();
    _set(_state.copyWith(
      phase: RunPhase.paused,
      reason: reason,
      clearNextAt: true,
    ));
  }

  Future<void> resume() async {
    if (_state.phase != RunPhase.paused || _program == null) return;
    // A pause can interrupt a scheduled delay. Let that loop observe its
    // generation change before starting the continuation.
    while (_runningLoop) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (_state.phase != RunPhase.paused || _program == null) return;
    _startAt = _now().subtract(
      (_program!.interval ?? Duration.zero) * _index,
    );
    if (_abortOperation != null) return;
    await _track(() => _run());
  }

  Future<void> abort() {
    if (_abortOperation != null) return _abortOperation!;
    _abortOperation = _abort().whenComplete(() {
      _abortOperation = null;
    });
    return _abortOperation!;
  }

  Future<void> _abort() async {
    if (_program == null ||
        const {RunPhase.completed, RunPhase.aborted, RunPhase.refused}
            .contains(_state.phase)) {
      return;
    }
    _generation++;
    _interruptDelay();
    // Let any camera request already sent settle before restoring settings.
    // The invalidated generation prevents subsequent frame requests.
    await _activeOperation;
    await _restore();
    _set(_state.copyWith(
      phase: RunPhase.aborted,
      clearNextAt: true,
      clearReason: true,
    ));
    _program = null;
  }

  void nudge(double ev) {
    final program = _program;
    if (program == null || !program.supportsNudge) return;
    _set(_state.copyWith(nudgeEv: (_state.nudgeEv + ev).clamp(-3, 3)));
  }

  Future<void> _run({bool autoFocusFirst = false}) async {
    if (_runningLoop) return;
    _runningLoop = true;
    final generation = ++_generation;
    _set(_state.copyWith(
      phase: RunPhase.running,
      clearReason: true,
    ));
    try {
      final program = _program!;
      while (_index < program.frameCount && generation == _generation) {
        final planned =
            _startAt!.add((program.interval ?? Duration.zero) * _index);
        _set(_state.copyWith(nextAt: planned));
        final wait = planned.difference(_now());
        if (wait > Duration.zero && !await _delay(wait, generation)) return;
        if (generation != _generation) return;
        if (_now().isAfter(planned)) {
          _log.add({
            'event': 'overrun',
            'frame': _index,
            'milliseconds': _now().difference(planned).inMilliseconds,
          });
        }
        var ok = await _executeFrame(generation,
            autoFocus: autoFocusFirst && _index == 0);
        if (generation != _generation) return;
        if (!ok) {
          if (!await _delay(const Duration(seconds: 1), generation)) return;
          if (generation != _generation) return;
          ok = await _executeFrame(generation,
              autoFocus: autoFocusFirst && _index == 0);
        }
        if (generation != _generation) return;
        if (!ok) {
          _set(_state.copyWith(
            phase: RunPhase.paused,
            reason: 'failure',
            clearNextAt: true,
          ));
          return;
        }
        _index++;
        _set(_state.copyWith(done: _index));
      }
      if (generation == _generation && _index == program.frameCount) {
        await _restore();
        _set(_state.copyWith(
          phase: RunPhase.completed,
          clearNextAt: true,
          clearReason: true,
        ));
        _program = null;
      }
    } finally {
      _runningLoop = false;
    }
  }

  Future<bool> _delay(Duration duration, int generation) async {
    if (duration <= Duration.zero) return generation == _generation;
    final completer = Completer<void>();
    _wake = completer;
    _timer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    if (identical(_wake, completer)) {
      _wake = null;
      _timer = null;
    }
    return generation == _generation;
  }

  void _interruptDelay() {
    _timer?.cancel();
    _timer = null;
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  Future<bool> _executeFrame(int generation, {required bool autoFocus}) async {
    final program = _program!;
    final step = await program.step(ProgramContext(
      state: _camera.state,
      nudgeEv: _state.nudgeEv,
      index: _index,
    ));
    if (generation != _generation) return false;
    for (final MapEntry(:key, :value) in step.params.entries) {
      if (_camera.state.params[key]?.current == value) continue;
      if (!await _write(key, value)) return false;
      if (generation != _generation) return false;
    }
    if (generation != _generation) return false;
    final records = await _camera.shootAndAwait(
      autoFocus: autoFocus,
      context: CaptureContext(
        source: CaptureSource.program,
        programRunId: _state.runId,
        recipeId: step.recipeId,
        effect: step.params['effect'] ?? _camera.state.value(ParamKey.effect),
      ),
    );
    if (records.isEmpty) return false;
    _log.add({'event': 'shot', 'frame': _index, 'files': records.first.files});
    return true;
  }

  Future<bool> _write(String key, String value) async {
    final outcome = await _camera.setParam(key, value);
    if (outcome is! WriteConfirmed) return false;
    _touched.add(key);
    return true;
  }

  Future<void> _restore() async {
    for (final key in _touched.toList().reversed) {
      final value = _snapshot[key];
      if (value == null || _camera.state.params[key]?.current == value) {
        continue;
      }
      final outcome = await _camera.setParam(key, value);
      if (outcome is! WriteConfirmed) {
        _log.add({'event': 'restoreFailed', 'key': key});
      }
    }
  }

  void _set(ProgramRunState next) {
    _state = next;
    _onState(next);
  }
}
