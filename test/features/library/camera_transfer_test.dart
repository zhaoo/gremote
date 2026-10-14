import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/features/library/camera_transfer.dart';

void main() {
  test('thumbnails are bounded and originals drain then pause the queue',
      () async {
    final gate = CameraTransferGate();
    final first = Completer<void>();
    final second = Completer<void>();
    final order = <String>[];
    final a = gate.thumbnail(() async {
      order.add('a');
      await first.future;
    });
    final b = gate.thumbnail(() async {
      order.add('b');
      await second.future;
    });
    final c = gate.thumbnail(() async {
      order.add('c');
    });
    await pumpEventQueue();
    expect(order, ['a', 'b']);
    final batch = gate.originals(() async {
      order.add('original');
    });
    first.complete();
    await pumpEventQueue();
    expect(order, ['a', 'b']);
    second.complete();
    await Future.wait([a, b, c, batch]);
    expect(order, ['a', 'b', 'original', 'c']);
  });
  test('a failed original releases waiting thumbnails', () async {
    final gate = CameraTransferGate();
    final hold = Completer<void>();
    final batch = gate.originals(() async {
      await hold.future;
      throw StateError('offline');
    });
    final error = expectLater(batch, throwsStateError);
    var thumbnailFinished = false;
    final thumb = gate.thumbnail(() async {
      thumbnailFinished = true;
    });
    await pumpEventQueue();
    expect(thumbnailFinished, false);
    hold.complete();
    await error;
    await thumb;
    expect(thumbnailFinished, true);
  });
  test('queued thumbnail never requests a stale camera after reconnect',
      () async {
    final gate = CameraTransferGate();
    final hold = Completer<void>();
    final batch = gate.originals(() => hold.future);
    var requests = 0;
    final queued = gate.thumbnail(() async {
      requests++;
    });
    gate.invalidate();
    hold.complete();
    await batch;
    try {
      await queued;
    } catch (_) {}
    expect(requests, 0);
  });
  test('reconnected batch waits for previous original to finish', () async {
    final gate = CameraTransferGate();
    final hold = Completer<void>();
    final order = <String>[];
    final first = gate.originals(() async {
      order.add('old');
      await hold.future;
    });
    final next = gate.originals(() async {
      order.add('new');
    });
    final nextHandled = next.then((_) => null, onError: (_) => null);
    await pumpEventQueue();
    expect(order, ['old']);
    hold.complete();
    await first;
    await nextHandled;
    expect(order, ['old', 'new']);
  });
}
