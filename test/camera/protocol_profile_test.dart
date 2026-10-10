import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/protocol/protocol_profile.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('profiles round-trip through JSON', () {
    final profile = ProtocolProfile(
      firmware: '2.10',
      writeEncoding: WriteEncoding.form,
      webSocket: WsSupport.supported,
      probedAt: DateTime.utc(2026, 10, 10),
    );
    final copy = ProtocolProfile.fromJson(profile.toJson());
    expect(copy.writeEncoding, WriteEncoding.form);
    expect(copy.webSocket, WsSupport.supported);
    expect(copy.probedAt, DateTime.utc(2026, 10, 10));
  });

  test('unknown enum names fall back to unknown', () {
    final profile = ProtocolProfile.fromJson(
        const <String, Object?>{
          'firmware': '2.10',
          'writeEncoding': 'xml',
          'webSocket': 3,
        });
    expect(profile.writeEncoding, WriteEncoding.unknown);
    expect(profile.webSocket, WsSupport.unknown);
  });

  test('the store keeps one profile per firmware', () async {
    final db = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    addTearDown(db.close);
    final store = ProtocolProfileStore(db);

    expect((await store.load('2.10')).writeEncoding, WriteEncoding.unknown);
    await store.save(const ProtocolProfile(
        firmware: '2.10', writeEncoding: WriteEncoding.json));
    expect((await store.load('2.10')).writeEncoding, WriteEncoding.json);
    expect((await store.load('2.20')).writeEncoding, WriteEncoding.unknown);
  });
}
