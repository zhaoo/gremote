import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/app_presence.dart';
import 'package:gremote/camera/capture/capture_tracker.dart';
import 'package:gremote/location/location_recording.dart';
import '../support/camera_harness.dart';

class LocationFixture implements LocationGateway {
  final controller = StreamController<LocationFix>.broadcast();
  bool allowed = true;
  int starts = 0;
  int stops = 0;
  @override
  Stream<LocationFix> get fixes => controller.stream;
  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'location runs only for enabled, connected and visible foreground shooting',
      () async {
    final fixture = LocationFixture();
    final harness = await CameraHarness.create(
        overrides: [locationGatewayProvider.overrideWithValue(fixture)]);
    addTearDown(harness.dispose);
    addTearDown(fixture.controller.close);
    final recording =
        harness.container.read(locationRecordingProvider.notifier);
    await recording.ready;
    await recording.setEnabled(true);
    expect(fixture.starts, 0);
    await harness.connect();
    await recording.sync();
    expect(fixture.starts, 0);
    harness.container.read(shootPageVisibleProvider.notifier).state = true;
    await recording.sync();
    expect(fixture.starts, 1);
    await recording.setForeground(false);
    expect(harness.container.read(locationRecordingProvider).active, isFalse);
    await recording.setForeground(true);
    expect(fixture.starts, 2);
    harness.container.read(shootPageVisibleProvider.notifier).state = false;
    await recording.sync();
    expect(harness.container.read(locationRecordingProvider).active, isFalse);
  });

  test('only a recent accurate fix is associated with a capture and persists',
      () async {
    final now = DateTime(2026, 10, 18, 12);
    final fixture = LocationFixture();
    final harness = await CameraHarness.create(overrides: [
      locationGatewayProvider.overrideWithValue(fixture),
      locationClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(harness.dispose);
    addTearDown(fixture.controller.close);
    final recording =
        harness.container.read(locationRecordingProvider.notifier);
    await recording.ready;
    await harness.connect();
    await recording.setEnabled(true);
    harness.container.read(shootPageVisibleProvider.notifier).state = true;
    await recording.sync();
    const shot = CaptureRecord(
        dir: '100RICOH',
        baseName: 'R001',
        files: ['R001.JPG', 'R001.DNG'],
        wallSeconds: 1,
        timeSource: TimeSource.camera,
        source: CaptureSource.app);
    fixture.controller.add(LocationFix(
        latitude: 31.2,
        longitude: 121.5,
        accuracy: 8,
        timestamp: now.subtract(const Duration(minutes: 2))));
    await Future<void>.delayed(Duration.zero);
    await recording.record(shot);
    expect(await harness.container.read(shotLocationStoreProvider).recent(),
        isEmpty);
    fixture.controller.add(LocationFix(
        latitude: 31.2, longitude: 121.5, accuracy: 8, timestamp: now));
    await Future<void>.delayed(Duration.zero);
    await recording.record(shot);
    final stored =
        await harness.container.read(shotLocationStoreProvider).recent();
    expect(stored, hasLength(1));
    expect(stored.single.baseName, 'R001');
    expect(stored.single.fix.latitude, 31.2);
    await recording.setEnabled(false);
    await recording.record(const CaptureRecord(
        dir: '100RICOH',
        baseName: 'R002',
        files: ['R002.JPG'],
        wallSeconds: 2,
        timeSource: TimeSource.camera,
        source: CaptureSource.app));
    expect(await harness.container.read(shotLocationStoreProvider).recent(),
        hasLength(1));
  });

  test(
      'denied permission never starts recording or persists enabled preference',
      () async {
    final fixture = LocationFixture()..allowed = false;
    final harness = await CameraHarness.create(
        overrides: [locationGatewayProvider.overrideWithValue(fixture)]);
    addTearDown(harness.dispose);
    addTearDown(fixture.controller.close);
    final recording =
        harness.container.read(locationRecordingProvider.notifier);
    await recording.ready;
    await recording.setEnabled(true);
    expect(harness.container.read(locationRecordingProvider).enabled, isFalse);
    expect(fixture.starts, 0);
  });
}
