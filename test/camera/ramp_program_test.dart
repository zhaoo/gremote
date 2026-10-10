import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/program/program.dart';
import 'package:gremote/camera/program/ramp_program.dart';
import 'package:gremote/camera/protocol/props_parser.dart';
import 'package:gremote/camera/sync/camera_state.dart';

CameraState _state({String mode = 'M'}) =>
    CameraState.offline.applyProps(parseProps({
      'exposureMode': mode,
      'exposureModeList': [mode],
      'tv': '1',
      'tvList': ['1/4', '1/2', '1', '2', '4', '8', '15', '30'],
      'sv': '100',
      'svList': ['auto', '100', '200', '400', '800', '1600'],
    }));

ProgramContext _context(int index, {double nudge = 0, CameraState? state}) =>
    ProgramContext(state: state ?? _state(), nudgeEv: nudge, index: index);

void main() {
  test('planned ramp interpolates exposure endpoints', () async {
    final program = PlannedRampProgram(
      start: const ExposurePair(tv: '1', sv: '100'),
      end: const ExposurePair(tv: '4', sv: '400'),
      frames: 3,
      interval: const Duration(seconds: 20),
      maxShutterSeconds: 30,
    );

    expect((await program.step(_context(0))).params, {'tv': '1', 'sv': '100'});
    expect((await program.step(_context(1))).params, {'tv': '4', 'sv': '100'});
    expect((await program.step(_context(2))).params, {'tv': '15', 'sv': '100'});
  });

  test('after shutter cap the ramp raises ISO', () async {
    final program = PlannedRampProgram(
      start: const ExposurePair(tv: '1', sv: '100'),
      end: const ExposurePair(tv: '4', sv: '400'),
      frames: 3,
      interval: const Duration(seconds: 5),
      maxShutterSeconds: 2,
    );

    expect((await program.step(_context(0))).params, {'tv': '1', 'sv': '100'});
    expect((await program.step(_context(1))).params, {'tv': '2', 'sv': '200'});
    expect((await program.step(_context(2))).params, {'tv': '2', 'sv': '800'});
  });

  test('nudge shifts the exposure in EV', () async {
    final program = PlannedRampProgram(
      start: const ExposurePair(tv: '1', sv: '100'),
      end: const ExposurePair(tv: '1', sv: '100'),
      frames: 2,
      interval: const Duration(seconds: 5),
    );
    expect((await program.step(_context(0, nudge: 1))).params,
        {'tv': '2', 'sv': '100'});
  });

  test('metered ramp applies dead zone and clamps each correction to one third',
      () async {
    final readings = <double?>[0.5, 0.46, 0.25];
    final program = MeteredRampProgram(
      start: const ExposurePair(tv: '1', sv: '100'),
      end: const ExposurePair(tv: '1', sv: '100'),
      frames: 3,
      interval: const Duration(seconds: 5),
      meter: () async => readings.removeAt(0),
    );

    await program.step(_context(0));
    expect(program.meterOffsetEv, 0);
    await program.step(_context(1));
    expect(program.meterOffsetEv, 0, reason: 'inside the 1/6 EV dead zone');
    await program.step(_context(2));
    expect(program.meterOffsetEv, closeTo(1 / 3, 1e-9));
  });

  test('requires M mode, writable lists and numeric base ISO', () {
    final program = PlannedRampProgram(
      start: const ExposurePair(tv: '1', sv: 'auto'),
      end: const ExposurePair(tv: '2', sv: '200'),
      frames: 2,
      interval: const Duration(seconds: 5),
    );
    expect(program.refusal(_state()), isNotNull);

    final numeric = PlannedRampProgram(
      start: const ExposurePair(tv: '1', sv: '100'),
      end: const ExposurePair(tv: '2', sv: '200'),
      frames: 2,
      interval: const Duration(seconds: 5),
    );
    expect(numeric.refusal(_state(mode: 'Av')), contains('M'));
    expect(numeric.refusal(_state()), isNull);
  });
}
