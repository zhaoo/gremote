import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/app_presence.dart';
import 'package:gremote/camera/program/program.dart';
import 'package:gremote/camera/program/program_controller.dart';
import 'package:gremote/camera/program/program_runner.dart';

import '../support/camera_harness.dart';

class _Program implements Program {
  _Program({this.frames = 1, this.gap});
  final int frames;
  final Duration? gap;
  @override
  String get kind => 'controllerTest';
  @override
  String get label => '测试';
  @override
  int get frameCount => frames;
  @override
  Duration? get interval => gap;
  @override
  bool get supportsNudge => true;
  @override
  String? refusal(state) => null;
  @override
  Future<ProgramStep> step(ProgramContext context) async => const ProgramStep();
}

void main() {
  test('running keeps the screen awake, saves the run, then releases it',
      () async {
    final h = await CameraHarness.create();
    addTearDown(h.dispose);
    await h.connect();
    final controller = h.container.read(programControllerProvider.notifier);

    await controller.start(_Program());
    await pumpEventQueue();

    expect(h.gateways.trace, containsAllInOrder([
      'keepScreenOn:true',
      'keepScreenOn:false',
    ]));
    expect(h.container.read(programControllerProvider).phase,
        RunPhase.completed);
    expect((await h.db.query('program_runs')).single['state'], 'completed');
  });

  test('background pauses and resume continues the same run', () async {
    final h = await CameraHarness.create();
    addTearDown(h.dispose);
    await h.connect();
    final controller = h.container.read(programControllerProvider.notifier);

    final running = controller.start(
        _Program(frames: 2, gap: const Duration(seconds: 1)));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    h.container.read(appForegroundProvider.notifier).state = false;
    await pumpEventQueue();

    expect(h.container.read(programControllerProvider).phase, RunPhase.paused);
    expect(h.container.read(programControllerProvider).reason, 'background');
    expect(h.gateways.trace.last, 'keepScreenOn:true');

    h.container.read(appForegroundProvider.notifier).state = true;
    await controller.resume();
    await running;
    expect(h.container.read(programControllerProvider).phase,
        RunPhase.completed);
  });

  test('hot camera refuses a new program', () async {
    final h = await CameraHarness.create();
    addTearDown(h.dispose);
    await h.connect();
    h.camera.props['hot'] = true;
    await h.controller.refresh();
    expect(h.state.status.hot, isTrue);

    await h.container.read(programControllerProvider.notifier).start(_Program());

    expect(h.container.read(programControllerProvider).phase, RunPhase.refused);
    expect(h.container.read(programControllerProvider).reason, contains('温度'));
  });
}
