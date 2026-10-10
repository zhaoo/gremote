import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/diagnostics/diagnostic_event.dart';
import 'package:gremote/diagnostics/diagnostic_redactor.dart';
import 'package:gremote/diagnostics/diagnostic_store.dart';

void main() {
  test('redacts every sensitive field and preserves protocol evidence', () {
    const event = DiagnosticEvent(
      stage: 'probing',
      monotonicMicros: 123456,
      durationMs: 420,
      firmware: '2.10',
      statusCode: 200,
      endpointPath: '/v1/ping?key=secret-password',
      exceptionCode: 'cameraProbeFailed',
      retryCount: 2,
      ssid: 'RICOH_PRIVATE',
      passphrase: 'secret-password',
      deviceAddress: 'AA:BB:CC:DD:EE:FF',
      serialNumber: '1234567890',
      filePath: '/Users/alice/DCIM/private.jpg',
      latitude: 31.2304,
      longitude: 121.4737,
      httpBody: '{"password":"secret-password"}',
    );

    final json = jsonEncode(DiagnosticRedactor.redact(event));

    for (final secret in [
      'RICOH_PRIVATE',
      'secret-password',
      'AA:BB:CC:DD:EE:FF',
      '1234567890',
      '/Users/alice/DCIM/private.jpg',
      '31.2304',
      '121.4737',
    ]) {
      expect(json, isNot(contains(secret)));
    }
    expect(json, contains('probing'));
    expect(json, contains('123456'));
    expect(json, contains('420'));
    expect(json, contains('2.10'));
    expect(json, contains('200'));
    expect(json, contains('/v1/ping'));
    expect(json, contains('cameraProbeFailed'));
    expect(json, contains('"retryCount":2'));
    expect(json, contains('<redacted:ssid>'));
  });

  test('store bounds memory to 2000 and persistence to 500 events', () async {
    final persistence = _MemoryPersistence();
    final store = DiagnosticStore(persistence: persistence);

    for (var index = 0; index < 2001; index++) {
      store.record(
        DiagnosticEvent(
          stage: 'ble',
          monotonicMicros: index,
          durationMs: 1,
          retryCount: index,
        ),
      );
    }
    await store.persist();

    final exported = jsonDecode(store.exportJson()) as Map<String, Object?>;
    final memoryEvents = exported['events']! as List<Object?>;
    final persisted = jsonDecode(persistence.value!) as Map<String, Object?>;
    final persistedEvents = persisted['events']! as List<Object?>;
    expect(exported['schema'], 'gremote-diagnostics/1');
    expect(memoryEvents, hasLength(2000));
    expect((memoryEvents.first! as Map<String, Object?>)['retryCount'], 1);
    expect(persistedEvents, hasLength(500));
    expect(
        (persistedEvents.first! as Map<String, Object?>)['retryCount'], 1501);
  });
}

class _MemoryPersistence implements DiagnosticPersistence {
  String? value;

  @override
  Future<void> write(String json) async => value = json;
}
