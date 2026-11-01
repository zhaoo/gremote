import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/media/local/media_gateway.dart';
import '../support/test_darkroom.dart';
import '../support/fake_media_gateway.dart';
import 'package:gremote/media/local/local_media_repository.dart';

void main() {
  test(
      'collection includes downloads and explicit imports, excludes unrelated photos',
      () async {
    final gateway = FakeMediaGateway(entries: [
      const LocalMediaEntry(
          id: 1,
          uri: 'content://images/1',
          displayName: 'GR.jpg',
          dateModified: 1,
          appAlbum: true),
      const LocalMediaEntry(
          id: 2,
          uri: 'content://images/2',
          displayName: 'phone.jpg',
          dateModified: 1),
    ], exif: {
      1: grMeta(),
      2: grMeta()
    });
    final env = await TestDarkroom.create(gateway: gateway);
    addTearDown(env.close);
    final repo = LocalMediaRepository(env.db, gateway);
    await repo.scan().drain<void>();
    expect((await repo.album()).map((e) => e.id), [1]);
    await repo.addToAlbum(2, source: 'import');
    expect((await repo.album()).map((e) => e.id).toSet(), {1, 2});
    await repo.scan().drain<void>();
    expect((await repo.album()).length, 2);
  });
}
