import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/gateway/change_socket.dart';
import 'package:gremote/camera/protocol/protocol_profile.dart';
import 'package:gremote/camera/sync/camera_state.dart';
import 'package:gremote/camera/sync/change_stream.dart';

class _Socket implements ChangeSocket {
  _Socket(this.now, {this.accept = true});

  final controller = StreamController<ChangeSocketEvent>.broadcast(sync: true);
  final openTimes = <Duration>[];
  final Duration Function() now;
  bool accept;

  @override
  Stream<ChangeSocketEvent> get events => controller.stream;

  @override
  Future<void> open(String path) async {
    openTimes.add(now());
    controller.add(
        accept ? const ChangeSocketOpened() : const ChangeSocketFailed(404));
  }

  @override
  Future<void> close() async {}
}

class _Harness {
  _Harness(FakeAsync async,
      {bool accept = true, WsSupport support = WsSupport.unknown}) {
    socket = _Socket(() => async.elapsed, accept: accept);
    stream = ChangeStream(
      socket: socket,
      fetchProps: () async {
        fetches++;
        return {'av': '2.8'};
      },
      onProps: (json, {required full}) => props.add((json, full)),
      onMode: modes.add,
      onSupport: supports.add,
      initialSupport: support,
    );
  }

  late final _Socket socket;
  late final ChangeStream stream;
  var fetches = 0;
  final props = <(Map<String, Object?>, bool)>[];
  final modes = <SyncMode>[];
  final supports = <WsSupport>[];
}

void main() {
  test('socket messages merge as partial props', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.stream.start();
      async.flushMicrotasks();

      expect(h.modes, [SyncMode.polling, SyncMode.webSocket]);
      expect(h.supports, [WsSupport.supported]);
      expect(h.props.single.$2, isTrue, reason: 'refresh after open');

      h.socket.controller.add(const ChangeSocketMessage('{"av":"4.0"}'));
      h.socket.controller.add(const ChangeSocketMessage('not json'));
      expect(h.props.last.$1, {'av': '4.0'});
      expect(h.props.last.$2, isFalse);
      expect(h.props, hasLength(2));
      h.stream.stop();
    });
  });

  test('three failed handshakes switch to polling for good', () {
    fakeAsync((async) {
      final h = _Harness(async, accept: false);
      h.stream.setPollingAllowed(true);
      h.stream.start();
      async.elapse(const Duration(seconds: 10));

      expect(h.socket.openTimes, hasLength(3));
      expect(h.supports, [WsSupport.unsupported]);
      expect(h.stream.mode, SyncMode.polling);
      final before = h.fetches;
      async.elapse(const Duration(seconds: 5));
      expect(h.fetches - before, 5);
      expect(h.socket.openTimes, hasLength(3));
      h.stream.stop();
    });
  });

  test('a dropped socket reconnects with backoff', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.stream.start();
      async.flushMicrotasks();
      h.socket.accept = false;
      h.socket.controller.add(const ChangeSocketClosed(1006));
      async.elapse(const Duration(seconds: 40));

      final gaps = [
        for (var i = 1; i < h.socket.openTimes.length; i++)
          (h.socket.openTimes[i] - h.socket.openTimes[i - 1]).inSeconds,
      ];
      expect(gaps.take(5), [1, 2, 4, 8, 16]);
      expect(h.supports, [WsSupport.supported]);
      h.stream.stop();
    });
  });

  test('no polling while not allowed; unsupported skips the socket', () {
    fakeAsync((async) {
      final h = _Harness(async, support: WsSupport.unsupported);
      h.stream.start();
      async.elapse(const Duration(seconds: 3));
      expect(h.fetches, 0);
      expect(h.socket.openTimes, isEmpty);

      h.stream.setPollingAllowed(true);
      async.elapse(const Duration(seconds: 3));
      expect(h.fetches, 3);
      h.stream.setPollingAllowed(false);
      async.elapse(const Duration(seconds: 3));
      expect(h.fetches, 3);
      h.stream.stop();
      expect(h.modes.last, SyncMode.offline);
    });
  });
}
