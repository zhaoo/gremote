import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/capture/capture_tracker.dart';
import 'package:gremote/camera/params/camera_param.dart';
import 'package:gremote/camera/params/param_writer.dart';
import 'package:gremote/camera/program/program.dart';
import 'package:gremote/camera/program/program_runner.dart';
import 'package:gremote/camera/protocol/props_parser.dart';
import 'package:gremote/camera/sync/camera_state.dart';

CameraState _state() => CameraState.offline.applyProps(parseProps({
      'shootMode': 'continuous',
      'shootModeList': ['single', 'continuous'],
      'av': '2.8',
      'avList': ['2.8', '4.0'],
      'effect': 'standard',
      'effectList': ['standard', 'vivid'],
    }));

class _Camera implements ProgramCamera {
  @override
  CameraState state = _state();
  final writes = <String>[];
  final shots = <CaptureContext>[];
  var failures = 0;

  @override
  Future<WriteOutcome> setParam(String wireKey, String value) async {
    writes.add('$wireKey=$value');
    state = state.applyProps(parseProps({wireKey: value}));
    return WriteConfirmed(value);
  }

  @override
  Future<List<CaptureRecord>> shootAndAwait({
    required bool autoFocus,
    required CaptureContext context,
  }) async {
    if (failures-- > 0) return const [];
    shots.add(context);
    return [
      CaptureRecord(
        dir: '100RICOH',
        baseName: 'R${shots.length}',
        files: ['R${shots.length}.JPG'],
        wallSeconds: shots.length,
        timeSource: TimeSource.phone,
        source: context.source,
      ),
    ];
  }
}

class _Program implements Program {
  _Program({this.frames = 3, this.delay = const Duration(seconds: 1)});
  final int frames;
  final Duration? delay;

  @override
  String get kind => 'test';
  @override
  String get label => '测试';
  @override
  int get frameCount => frames;
  @override
  Duration? get interval => delay;
  @override
  bool get supportsNudge => true;
  @override
  String? refusal(CameraState state) => null;
  @override
  Future<ProgramStep> step(ProgramContext context) async => ProgramStep(
        params: {'av': context.index.isEven ? '4.0' : '2.8'},
        recipeId: 'recipe-${context.index}',
      );
}

void main() {
  test('runs frames at planned times and restores changed parameters', () {
    fakeAsync((async) {
      final camera = _Camera();
      final states = <ProgramRunState>[];
      final runner = ProgramRunner(
        camera: camera,
        onState: states.add,
        now: () => async.getClock(DateTime.utc(2026)).now(),
        newId: () => 'run-1',
      );
      var completed = false;
      runner.start(_Program()).then((_) => completed = true);
      async.flushMicrotasks();
      expect(camera.shots, hasLength(1));
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(completed, isTrue);
      expect(camera.shots, hasLength(3));
      expect(camera.shots.map((c) => c.recipeId),
          ['recipe-0', 'recipe-1', 'recipe-2']);
      expect(camera.writes.first, 'shootMode=single');
      expect(camera.state.value(ParamKey.drive), 'continuous');
      expect(camera.state.value(ParamKey.aperture), '2.8');
      expect(runner.state.phase, RunPhase.completed);
      expect(runner.log.where((e) => e['event'] == 'shot'), hasLength(3));
    });
  });

  test('one failed shot retries, two failures pause and resume same frame', () {
    fakeAsync((async) {
      final camera = _Camera()..failures = 2;
      final runner = ProgramRunner(
        camera: camera,
        onState: (_) {},
        now: () => async.getClock(DateTime.utc(2026)).now(),
      );
      runner.start(_Program(frames: 1, delay: null));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(runner.state.phase, RunPhase.paused);
      expect(runner.state.done, 0);

      runner.resume();
      async.flushMicrotasks();
      expect(runner.state.phase, RunPhase.completed);
      expect(camera.shots, hasLength(1));
    });
  });

  test('refusal stops before changing the camera', () {
    final camera = _Camera();
    final program = _RefusedProgram();
    final runner = ProgramRunner(camera: camera, onState: (_) {});
    return runner.start(program).then((_) {
      expect(runner.state.phase, RunPhase.refused);
      expect(runner.state.reason, 'not-ready');
      expect(camera.writes, isEmpty);
    });
  });
}

class _RefusedProgram extends _Program {
  @override
  String? refusal(CameraState state) => 'not-ready';
}
