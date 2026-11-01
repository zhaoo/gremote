import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/features/library/library_controller.dart';
import '../../support/fake_media_gateway.dart';
import '../../support/test_darkroom.dart';

void main() {
  test('refresh arriving during an EXIF scan is replayed after that scan',
      () async {
    final gate = Completer<void>(), started = Completer<void>();
    final gateway =
        FakeMediaGateway(entries: [mediaEntry(1)], exif: {1: grMeta()});
    gateway.beforeExif = () async {
      if (!started.isCompleted) {
        started.complete();
        await gate.future;
      }
    };
    final env = await TestDarkroom.create(gateway: gateway);
    addTearDown(env.close);
    final container = ProviderContainer(overrides: env.overrides);
    addTearDown(container.dispose);
    final controller = container.read(libraryControllerProvider.notifier);
    final first = controller.refresh();
    await started.future;
    gateway.entries = [mediaEntry(1), mediaEntry(2)];
    gateway.exif = {1: grMeta(), 2: grMeta()};
    await controller.refresh();
    gate.complete();
    await first;
    expect(
        container
            .read(libraryControllerProvider)
            .items
            .map((e) => e.id)
            .toSet(),
        {1, 2});
  });
}
