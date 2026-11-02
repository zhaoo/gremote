import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/features/home/home_cover_providers.dart';
import 'package:gremote/features/home/home_cover_settings.dart';
import 'package:gremote/media/local/local_media_repository.dart';
import 'package:gremote/media/local/media_gateway.dart';
import '../../support/test_darkroom.dart';
import '../../support/fake_media_gateway.dart';

class _Photos extends FakeMediaGateway {
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
  bool broken = false;
  @override
  Future<Uint8List?> thumbnail(int id, int edge) async =>
      broken ? Uint8List.fromList([0]) : png;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'revoked permission and deleted photos yield no old cover, keep saved intent',
      () async {
    final gateway = _Photos()..entries = [mediaEntry(1)];
    final env = await TestDarkroom.create(gateway: gateway);
    addTearDown(env.close);
    final repo = LocalMediaRepository(env.db, gateway);
    await repo.scan().drain<void>();
    await repo.addToAlbum(1, source: 'import');
    final container = ProviderContainer(overrides: env.overrides);
    addTearDown(container.dispose);
    final listener = container.listen(homeCoverDataProvider, (_, __) {});
    addTearDown(listener.close);
    final item = (await repo.album()).single;
    await container.read(homeCoverRepositoryProvider).save(HomeCoverSettings(
        entries: [HomeCoverEntry(id: item.id, uri: item.uri)]));
    expect(
        (await container.read(homeCoverDataProvider.future)).frames.length, 1);
    gateway.mediaAccess = MediaAccess.denied;
    container.invalidate(homeCoverDataProvider);
    expect(
        (await container.read(homeCoverDataProvider.future)).frames, isEmpty);
    gateway.mediaAccess = MediaAccess.granted;
    gateway.entries = [];
    container.invalidate(homeCoverDataProvider);
    expect(
        (await container.read(homeCoverDataProvider.future)).frames, isEmpty);
    expect(
        (await container.read(homeCoverRepositoryProvider).load())
            .entries
            .length,
        1);
    gateway.entries = [mediaEntry(1)];
    container.invalidate(homeCoverDataProvider);
    expect(
        (await container.read(homeCoverDataProvider.future)).frames.length, 1);
    gateway.broken = true;
    container.invalidate(homeCoverDataProvider);
    expect(
        (await container.read(homeCoverDataProvider.future)).frames, isEmpty);
    expect(gateway.publishes, isEmpty);
    expect(gateway.openedFds, isEmpty);
  });
}
