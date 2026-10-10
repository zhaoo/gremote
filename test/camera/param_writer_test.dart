import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/http/camera_api.dart';
import 'package:gremote/camera/params/camera_param.dart';
import 'package:gremote/camera/params/param_writer.dart';
import 'package:gremote/camera/protocol/protocol_profile.dart';

const _av = CameraParam(wireKey: 'av', current: '2.8', options: ['2.8', '4.0']);
const _sv = CameraParam(wireKey: 'sv', current: '200', options: ['200', '400']);

class _Harness {
  _Harness({this.encoding = WriteEncoding.query, this.accept});

  WriteEncoding encoding;
  final Set<WriteEncoding>? accept;
  final sent = <(String, WriteEncoding)>[];
  final camera = <String, String>{'av': '2.8', 'sv': '200'};
  final gates = <Completer<void>>[];
  bool gate = false;
  bool echo = false;
  bool disabled = false;
  String? Function(String key, String value)? correct;

  late final writer = ParamWriter(
    send: (endpoint, values, encoding) async {
      final MapEntry(:key, :value) = values.entries.single;
      sent.add(('$key=$value', encoding));
      if (gate) {
        final c = Completer<void>();
        gates.add(c);
        await c.future;
      }
      if (accept != null && !accept!.contains(encoding)) {
        throw const CameraApiException(
            code: 'httpStatus', path: '/v1/params/camera', statusCode: 400);
      }
      camera[key] = correct?.call(key, value) ?? value;
      return echo ? {key: camera[key]} : {};
    },
    refreshAndRead: (key) async => camera[key],
    encoding: () => encoding,
    rememberEncoding: (e) async => encoding = e,
    disableWrites: () => disabled = true,
  );
}

void main() {
  test('confirmed when readback equals the target', () async {
    final h = _Harness();
    expect(await h.writer.write(_av, '4.0'), isA<WriteConfirmed>());
  });

  test('corrected when the camera settles elsewhere', () async {
    final h = _Harness()..correct = (_, __) => '3.5';
    final outcome = await h.writer.write(_av, '4.0');
    expect(outcome, isA<WriteCorrected>());
    expect((outcome as WriteCorrected).actual, '3.5');
  });

  test('response echo is used without a refresh', () async {
    final h = _Harness()
      ..echo = true
      ..correct = (_, __) => '5.6';
    final outcome = await h.writer.write(_av, '4.0');
    expect((outcome as WriteCorrected).actual, '5.6');
  });

  test('one request in flight; newest queued value wins', () {
    fakeAsync((async) {
      final h = _Harness()..gate = true;
      final results = <WriteOutcome>[];
      h.writer.write(_av, '4.0').then(results.add);
      async.flushMicrotasks();
      h.writer.write(_sv, '400').then(results.add);
      h.writer.write(_av, '2.8').then(results.add);
      h.writer.write(_av, '4.0').then(results.add);
      async.flushMicrotasks();

      expect(h.sent, hasLength(1));
      expect(results.single, isA<WriteSuperseded>());

      h.gates.removeAt(0).complete();
      async.flushMicrotasks();
      expect(h.sent.map((s) => s.$1), ['av=4.0', 'sv=400']);
      h.gates.removeAt(0).complete();
      async.flushMicrotasks();
      h.gates.removeAt(0).complete();
      async.flushMicrotasks();

      expect(h.sent.map((s) => s.$1), ['av=4.0', 'sv=400', 'av=4.0']);
      expect(results, hasLength(4));
      expect(h.writer.busy, isFalse);
    });
  });

  test('unknown encoding falls back query → form → json and remembers',
      () async {
    final h =
        _Harness(encoding: WriteEncoding.unknown, accept: {WriteEncoding.json});
    expect(await h.writer.write(_av, '4.0'), isA<WriteConfirmed>());
    expect(h.sent.map((s) => s.$2),
        [WriteEncoding.query, WriteEncoding.form, WriteEncoding.json]);
    expect(h.encoding, WriteEncoding.json);

    await h.writer.write(_sv, '400');
    expect(h.sent.last.$2, WriteEncoding.json);
  });

  test('every encoding failing disables writes for the connection', () async {
    final h = _Harness(encoding: WriteEncoding.unknown, accept: {});
    expect(await h.writer.write(_av, '4.0'), isA<WritesDisabled>());
    expect(h.disabled, isTrue);
    expect(await h.writer.write(_sv, '400'), isA<WritesDisabled>());
    expect(h.sent, hasLength(3));
  });

  test('a known encoding failure is a rejection', () async {
    final h = _Harness(accept: {WriteEncoding.form});
    final outcome = await h.writer.write(_av, '4.0');
    expect(outcome, isA<WriteRejected>());
    expect((outcome as WriteRejected).code, 'httpStatus');
    expect(h.disabled, isFalse);
  });

  test('times out after three seconds', () {
    fakeAsync((async) {
      final h = _Harness()..gate = true;
      WriteOutcome? outcome;
      h.writer.write(_av, '4.0').then((o) => outcome = o);
      async.elapse(const Duration(seconds: 3));
      expect(outcome, isA<WriteTimedOut>());
      expect(h.writer.busy, isTrue);
      h.gates.single.complete();
      async.flushMicrotasks();
      expect(h.writer.busy, isFalse);
    });
  });
}
