import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/live/live_frame_analyzer.dart';
import 'package:gremote/camera/live/live_view_controller.dart';

import '../support/camera_harness.dart';

void main() {
  test('RGBA statistics return mean luma and a 64-bin histogram', () {
    final white = statsFromRgba(Uint8List.fromList([255, 255, 255, 255]));
    expect(white.meanLuma, closeTo(1, 1e-6));
    expect(white.histogram, hasLength(64));
    expect(white.histogram.last, 1);

    final black = statsFromRgba(Uint8List.fromList([0, 0, 0, 255]));
    expect(black.meanLuma, 0);
    expect(black.histogram.first, 1);
  });

  test('invalid RGBA length returns empty statistics', () {
    final stats = statsFromRgba(Uint8List.fromList([1, 2, 3]));
    expect(stats.meanLuma, 0);
    expect(stats.histogram.reduce((a, b) => a + b), 0);
  });

  test('attach starts Live View and detach stops after last reference',
      () async {
    final h = await CameraHarness.create();
    addTearDown(h.dispose);
    await h.connect();
    final controller = h.container.read(liveViewControllerProvider.notifier);

    controller.attach();
    controller.attach();
    await pumpEventQueue();
    expect(h.gateways.trace.where((e) => e == 'startLiveView'), hasLength(1));
    expect(h.container.read(liveViewControllerProvider), isNotNull);

    controller.detach();
    await pumpEventQueue();
    expect(h.gateways.trace.where((e) => e == 'stopLiveView'), isEmpty);
    controller.detach();
    await pumpEventQueue();
    expect(h.gateways.trace.where((e) => e == 'stopLiveView'), hasLength(1));
  });
}
