import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/app_presence.dart';
import 'package:gremote/camera/capture/capture_tracker.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/gateway/fake_camera_model.dart';
import 'package:gremote/camera/params/camera_param.dart';
import 'package:gremote/camera/params/param_writer.dart';
import 'package:gremote/camera/protocol/protocol_profile.dart';
import 'package:gremote/camera/sync/camera_state.dart';

import '../support/camera_harness.dart';

void main() {
  late CameraHarness h;

  tearDown(() => h.dispose());

  test('connecting loads params and opens the change socket', () async {
    h = await CameraHarness.create();
    await h.connect();

    expect(h.state.value(ParamKey.aperture), '2.8');
    expect(h.state.syncMode, SyncMode.webSocket);
    expect(h.gateways.trace, contains('openChanges'));
  });

  test('restores connection baseline rather than the latest shoot values',
      () async {
    h = await CameraHarness.create();
    await h.connect();
    await h.controller.setParam('sv', '400');
    h.camera.bodyChange('av', '5.6');
    await pumpEventQueue();
    final report = await h.controller.restoreConnectionSettings();
    expect(report.success, isTrue);
    expect(h.camera.props['sv'], '200');
    expect(h.camera.props['av'], '2.8');
    await h.controller.setParam('sv', '800');
    await h.controller.restoreConnectionSettings();
    expect(h.camera.props['sv'], '200');
  });

  test('restore reports changed settings whose baseline is no longer supported',
      () async {
    h = await CameraHarness.create();
    await h.connect();
    await h.controller.setParam('sv', '400');
    h.camera.props['svList'] = ['400', '800'];
    final report = await h.controller.restoreConnectionSettings();
    expect(report.success, isFalse);
    expect(report.failed, contains('sv'));
    expect(h.camera.props['sv'], '400');
  });

  test('restore drains pending writes and rejects edits while restoring',
      () async {
    h = await CameraHarness.create();
    await h.connect();
    final pending = h.controller.setParam('sv', '400');
    final restore = h.controller.restoreConnectionSettings();
    final edit = await h.controller.setParam('sv', '800');
    expect(edit, isA<WriteRejected>());
    await pending;
    expect((await restore).success, isTrue);
    expect(h.camera.props['sv'], '200');
  });

  test('restore reports a disconnected camera without issuing writes',
      () async {
    h = await CameraHarness.create();
    await h.connect();
    await h.controller.setParam('sv', '400');
    await h.container.read(connectionControllerProvider.notifier).cancel();
    final writeCount = h.camera.writes.length;
    final report = await h.controller.restoreConnectionSettings();
    expect(report.failed['connection'], 'offline');
    expect(h.camera.writes.length, writeCount);
  });

  test('setParam writes, remembers the encoding and reads back', () async {
    h = await CameraHarness.create(
        camera: FakeCameraModel(acceptedContentTypes: {'form'}));
    await h.connect();

    final outcome = await h.controller.setParam('sv', '400');

    expect(outcome, isA<WriteConfirmed>());
    expect(h.state.value(ParamKey.iso), '400');
    expect(h.state.pending, isEmpty);
    expect(h.controller.profile!.writeEncoding, WriteEncoding.form);
    final stored =
        await h.container.read(protocolProfileStoreProvider).load('2.10');
    expect(stored.writeEncoding, WriteEncoding.form);
  });

  test('body changes arrive through the socket', () async {
    h = await CameraHarness.create();
    await h.connect();

    h.camera.bodyChange('av', '5.6');
    await pumpEventQueue();

    expect(h.state.value(ParamKey.aperture), '5.6');
  });

  test('no working encoding makes the session read-only', () async {
    h = await CameraHarness.create(
        camera: FakeCameraModel(acceptedContentTypes: {}));
    await h.connect();

    expect(await h.controller.setParam('sv', '400'), isA<WritesDisabled>());
    expect(h.state.writesEnabled, isFalse);
    expect(await h.controller.setParam('av', '4.0'), isA<WritesDisabled>());
  });

  test('without WebSocket the state polls only while the page is visible',
      () async {
    h = await CameraHarness.create(camera: FakeCameraModel(webSocket: false));
    await h.connect();
    for (var i = 0; i < 3; i++) {
      h.camera.dropSocket();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(h.state.syncMode, SyncMode.polling);

    h.container.read(shootPageVisibleProvider.notifier).state = true;
    h.camera.props['av'] = '8.0';
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(h.state.value(ParamKey.aperture), '8.0');
  });

  test('shootAndAwait returns the new capture with its effect', () async {
    h = await CameraHarness.create();
    await h.connect();

    final records = await h.controller.shootAndAwait(
      autoFocus: false,
      context: const CaptureContext(
          source: CaptureSource.program, effect: 'standard'),
    );

    expect(records.single.baseName, 'R0000001');
    expect(records.single.timeSource, TimeSource.camera);
    expect(records.single.source, CaptureSource.program);
  });

  test('a body shot is detected from the remain drop', () async {
    h = await CameraHarness.create();
    await h.connect();
    final next = h.controller.captures.first;

    h.camera.shutter();

    final record = await next;
    expect(record.source, CaptureSource.body);
  });

  test('disconnecting returns to offline', () async {
    h = await CameraHarness.create();
    await h.connect();

    await h.container.read(connectionControllerProvider.notifier).cancel();
    await pumpEventQueue();

    expect(h.state.syncMode, SyncMode.offline);
    expect(h.state.params, isEmpty);
  });
}
