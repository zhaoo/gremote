import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/imaging/gpu/gpu_editor.dart';
import 'package:gremote/darkroom/model/photo_edits.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gremote/gpu_editor_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('owned source descriptor closes even if channel open fails', () async {
    final closed = <int>[];
    final service = GpuEditor(channel: channel, closeFd: closed.add);
    await expectLater(
        service.open(fd: 42, mediaId: 9, orientation: 1, processVersion: 2),
        throwsA(isA<MissingPluginException>()));
    expect(closed, [42]);
    service.dispose();
  });
  test('superseded LUT preparation cannot revive an old draft', () async {
    final prepare = Completer<void>(), updates = <int>[];
    final closed = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'open') {
        return {
          'sessionId': 1,
          'textureId': 2,
          'sourceWidth': 6000,
          'sourceHeight': 4000,
          'capabilities': '{}'
        };
      }
      if (call.method == 'prepareLut') await prepare.future;
      if (call.method == 'update') {
        updates.add((call.arguments as Map)['generation'] as int);
        return true;
      }
      return true;
    });
    final service = GpuEditor(channel: channel, closeFd: closed.add);
    final session = await service.open(
        fd: 43, mediaId: 9, orientation: 1, processVersion: 2);
    final a = session.update(
        edits: const PhotoEdits(),
        lutKey: 'old',
        cube: Uint8List.fromList([1]),
        strength: 1,
        width: 1200,
        height: 800);
    await Future<void>.delayed(Duration.zero);
    session.invalidate();
    prepare.complete();
    await a;
    expect(updates, isEmpty);
    expect(closed, [43]);
    await session.close();
    service.dispose();
  });
  test('cancelled generation cannot publish over the replacement frame',
      () async {
    final updates = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'open') {
        return {
          'sessionId': 1,
          'textureId': 2,
          'sourceWidth': 6000,
          'sourceHeight': 4000,
          'capabilities': '{}'
        };
      }
      if (call.method == 'update') {
        updates.add((call.arguments as Map)['generation'] as int);
        return true;
      }
      return true;
    });
    final service = GpuEditor(channel: channel, closeFd: (_) {});
    final session = await service.open(
        fd: 10, mediaId: 9, orientation: 1, processVersion: 2);
    final old = session.update(
        edits: const PhotoEdits(), strength: 1, width: 1200, height: 800);
    await Future<void>.delayed(Duration.zero);
    final oldGeneration = updates.last;
    session.invalidate();
    await old;
    final next = session.update(
        edits: const PhotoEdits().withValue(PhotoAdjustment.exposure, 1),
        strength: 1,
        width: 1200,
        height: 800);
    await Future<void>.delayed(Duration.zero);
    Future<void> frame(int generation) async {
      final done = Completer<void>();
      messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall('frame', {
            'sessionId': 1,
            'generation': generation,
            'width': 1200,
            'height': 800
          })),
          (_) => done.complete());
      await done.future;
    }

    final seen = <int>[];
    final subscription = session.frames.listen((f) => seen.add(f.generation));
    await frame(oldGeneration);
    expect(seen, isEmpty);
    await frame(updates.last);
    final result = await next;
    expect(result!.descriptor.edits.value(PhotoAdjustment.exposure), 1);
    expect(seen, [updates.last]);
    await subscription.cancel();
    await session.close();
    service.dispose();
  });
}
