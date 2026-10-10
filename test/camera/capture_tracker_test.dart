import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/capture/capture_tracker.dart';
import 'package:gremote/camera/http/camera_files.dart';

class _Camera {
  final files = <CameraFile>[];
  final times = <String, int>{};

  void add(String name) => files.add(CameraFile(dir: '100RICOH', file: name));

  late final tracker = CaptureTracker(
    listPhotos: () async => List.of(files),
    captureWallSeconds: (f) async => times[f.baseName],
    phoneSeconds: () => 999,
  );
}

const _app = CaptureContext(source: CaptureSource.app, effect: 'vivid');

void main() {
  test('RAW+JPEG of one shot become one record with camera time', () async {
    final camera = _Camera()..add('R0000001.JPG');
    await camera.tracker.prime();
    camera
      ..add('R0000002.JPG')
      ..add('R0000002.DNG')
      ..times['R0000002'] = 1234;

    final records =
        await camera.tracker.detect(_app, timeout: const Duration(seconds: 10));

    expect(records, hasLength(1));
    expect(records.single.files, ['R0000002.JPG', 'R0000002.DNG']);
    expect(records.single.wallSeconds, 1234);
    expect(records.single.timeSource, TimeSource.camera);
    expect(records.single.effect, 'vivid');
  });

  test('missing camera time falls back to the phone clock', () async {
    final camera = _Camera();
    await camera.tracker.prime();
    camera.add('R0000001.JPG');
    final record = (await camera.tracker
            .detect(_app, timeout: const Duration(seconds: 10)))
        .single;
    expect(record.wallSeconds, 999);
    expect(record.timeSource, TimeSource.phone);
  });

  test('a late RAW of a recorded JPEG is not a new shot', () async {
    final camera = _Camera();
    await camera.tracker.prime();
    camera.add('R0000001.JPG');
    await camera.tracker.detect(_app, timeout: Duration.zero);
    camera.add('R0000001.DNG');
    expect(await camera.tracker.detect(_app, timeout: Duration.zero), isEmpty);
  });

  test('times out with an empty list and polls once per second', () {
    fakeAsync((async) {
      final camera = _Camera();
      camera.tracker.prime();
      async.flushMicrotasks();
      List<CaptureRecord>? result;
      camera.tracker
          .detect(_app, timeout: const Duration(seconds: 10))
          .then((r) => result = r);
      async.elapse(const Duration(seconds: 3));
      expect(result, isNull);
      async.elapse(const Duration(seconds: 8));
      expect(result, isEmpty);
    });
  });

  test('concurrent detects share one diff; app context wins over body', () {
    fakeAsync((async) {
      final camera = _Camera();
      camera.tracker.prime();
      async.flushMicrotasks();
      final results = <List<CaptureRecord>>[];
      camera.tracker
          .detect(const CaptureContext(source: CaptureSource.body),
              timeout: const Duration(seconds: 10))
          .then(results.add);
      async.flushMicrotasks();
      camera.tracker
          .detect(_app, timeout: const Duration(seconds: 10))
          .then(results.add);
      camera.add('R0000001.JPG');
      async.elapse(const Duration(seconds: 1));

      expect(results, hasLength(2));
      expect(identical(results[0], results[1]), isTrue);
      expect(results[0].single.source, CaptureSource.app);
    });
  });

  test('timeout scales with the shutter speed', () {
    expect(CaptureTracker.timeoutFor('1/250'), const Duration(seconds: 10));
    expect(CaptureTracker.timeoutFor('15'), const Duration(seconds: 35));
    expect(CaptureTracker.timeoutFor(null), const Duration(seconds: 10));
  });
}
