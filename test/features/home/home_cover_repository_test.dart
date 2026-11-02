import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/features/home/home_cover_repository.dart';
import 'package:gremote/features/home/home_cover_settings.dart';
import 'package:gremote/media/local/local_media_repository.dart';
import '../../support/test_darkroom.dart';
import '../../support/fake_media_gateway.dart';

void main() {
  LocalMediaItem item(int id) => LocalMediaItem(
      id: id,
      uri: 'content://images/$id',
      displayName: '$id.jpg',
      dateModified: id);
  test(
      'recent covers use import time instead of shooting date, limited to five',
      () async {
    final gateway =
        FakeMediaGateway(entries: [for (var i = 1; i <= 6; i++) mediaEntry(i)]);
    final env = await TestDarkroom.create(gateway: gateway);
    addTearDown(env.close);
    final repo = LocalMediaRepository(env.db, gateway);
    await repo.scan().drain<void>();
    for (var i = 1; i <= 6; i++) {
      await repo.addToAlbum(i, source: 'import');
      await env.db.update('album_collection', {'added_at': 100 - i},
          where: 'media_id=?', whereArgs: [i]);
    }
    expect((await repo.recentAlbumImports()).map((e) => e.id), [1, 2, 3, 4, 5]);
  });
  test('settings persist order, framing and explicit default across reload',
      () async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    final repo = HomeCoverRepository(env.db);
    await repo.save(HomeCoverSettings(autoplay: false, entries: [
      HomeCoverEntry(id: 2, uri: item(2).uri, x: -.5, y: .7),
      HomeCoverEntry(id: 1, uri: item(1).uri)
    ]));
    final saved = await repo.load();
    expect(saved.autoplay, false);
    expect(saved.entries.map((e) => e.id), [2, 1]);
    expect(saved.entries.first.y, .7);
    await repo.save(const HomeCoverSettings(useDefault: true));
    expect(resolveCoverItems(await repo.load(), [item(1)]), isEmpty);
  });
  test(
      'missing and recycled media references are skipped without altering selection',
      () {
    final settings = HomeCoverSettings(entries: [
      const HomeCoverEntry(id: 2, uri: 'deleted'),
      HomeCoverEntry(id: 1, uri: item(1).uri)
    ]);
    expect(
        resolveCoverItems(settings, [item(1), item(2)]).map((e) => e.id), [1]);
    expect(settings.entries.length, 2);
  });
  test('invalid config is rejected without overwriting original record',
      () async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    final raw = jsonEncode({'version': 100, 'entries': []});
    await env.db.insert('app_kv', {'key': 'home.cover.v1', 'value': raw});
    await expectLater(
        HomeCoverRepository(env.db).load(), throwsFormatException);
    expect((await env.db.query('app_kv')).single['value'], raw);
    expect(
        () => HomeCoverSettings.fromJson({
              'version': 1,
              'autoplay': true,
              'useDefault': false,
              'entries': [
                {'id': 1, 'uri': 'x', 'x': 2, 'y': 0}
              ]
            }),
        throwsFormatException);
  });
}
