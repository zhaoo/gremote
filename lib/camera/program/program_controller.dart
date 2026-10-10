import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_presence.dart';
import '../capture/capture_tracker.dart';
import '../connection/connection_controller.dart';
import '../connection/connection_state.dart';
import '../params/param_writer.dart';
import '../recipe/recipe_store.dart';
import '../sync/camera_state.dart';
import '../sync/camera_state_controller.dart';
import 'program.dart';
import 'program_runner.dart';

final programControllerProvider =
    NotifierProvider<ProgramController, ProgramRunState>(
  ProgramController.new,
);

class _CameraAdapter implements ProgramCamera {
  _CameraAdapter(this.ref);

  final Ref ref;

  CameraStateController get _controller =>
      ref.read(cameraStateControllerProvider.notifier);

  @override
  CameraState get state => ref.read(cameraStateControllerProvider);

  @override
  Future<WriteOutcome> setParam(String wireKey, String value) =>
      _controller.setParam(wireKey, value);

  @override
  Future<List<CaptureRecord>> shootAndAwait({
    required bool autoFocus,
    required CaptureContext context,
  }) =>
      _controller.shootAndAwait(autoFocus: autoFocus, context: context);
}

class ProgramController extends Notifier<ProgramRunState> {
  late ProgramRunner _runner;
  DateTime? _startedAt;
  String? _savedRun;

  @override
  ProgramRunState build() {
    _runner = ProgramRunner(
      camera: _CameraAdapter(ref),
      onState: _onRunnerState,
    );
    ref.listen(appForegroundProvider, (_, foreground) {
      if (!foreground) _runner.pause('background');
    });
    ref.listen(connectionControllerProvider, (_, connection) {
      if (connection is! ConnectionReady) _runner.pause('disconnected');
    });
    ref.listen(cameraStateControllerProvider, (_, camera) {
      if (camera.status.hot == true) _runner.pause('hot');
    });
    final screen = ref.read(cameraGatewaysProvider).screen;
    ref.onDispose(() => unawaited(screen.setKeepScreenOn(false)));
    return const ProgramRunState();
  }

  Future<void> start(Program program) async {
    if (ref.read(cameraStateControllerProvider).status.hot == true) {
      _emit(ProgramRunState(
        phase: RunPhase.refused,
        kind: program.kind,
        total: program.frameCount,
        reason: '相机温度过高，请等待降温',
      ));
      return;
    }
    _startedAt = DateTime.now();
    _savedRun = null;
    await _runner.start(program);
  }

  void pause() => _runner.pause('user');
  Future<void> resume() => _runner.resume();
  Future<void> abort() => _runner.abort();
  void nudge(double ev) => _runner.nudge(ev);

  void _onRunnerState(ProgramRunState next) {
    state = next;
    unawaited(_sideEffects(next));
  }

  void _emit(ProgramRunState next) {
    state = next;
    unawaited(_sideEffects(next));
  }

  Future<void> _sideEffects(ProgramRunState next) async {
    final keepAwake =
        next.phase == RunPhase.running || next.phase == RunPhase.paused;
    await ref.read(cameraGatewaysProvider).screen.setKeepScreenOn(keepAwake);
    if (const {RunPhase.completed, RunPhase.aborted, RunPhase.refused}
            .contains(next.phase) &&
        next.runId != null &&
        _savedRun != next.runId) {
      _savedRun = next.runId;
      final started = _startedAt ?? DateTime.now();
      await ref.read(recipeStoreProvider).saveRun({
        'id': next.runId,
        'kind': next.kind ?? 'unknown',
        'config': {'total': next.total},
        'state': next.phase.name,
        'done': next.done,
        'startedAt': started.millisecondsSinceEpoch ~/ 1000,
        'endedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'log': _runner.log,
      });
    }
  }
}
