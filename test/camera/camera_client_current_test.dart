import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/companion_client.dart';
import 'package:gremote/camera/companion/companion_transport.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/camera/gateway/camera_transport.dart';
import 'camera_film_contract_test.dart';
import 'companion_client_test.dart' show key, identity, Keys;

class BusyWire implements CompanionTransport {
  int reads = 0, busy = 2;
  final sequences = <String>[];
  @override
  Future<CameraResponse> request(
      {required String method,
      required String path,
      required Map<String, String> headers,
      required Uint8List body}) async {
    final caps = path.endsWith('/capabilities');
    if (!caps) {
      reads++;
      sequences.add(headers['X-M10V-Seq']!);
    }
    final status = !caps && reads <= busy ? 503 : 200;
    final raw = Uint8List.fromList(utf8.encode(jsonEncode(caps
        ? cameraCapabilitiesFixture()
        : status == 503
            ? {
                'error': {'code': 'busy'}
              }
            : cameraStateFixture())));
    final boot = '02' * 16, session = '05' * 16;
    final signed = [
      'RESPONSE',
      method,
      path,
      boot,
      session,
      headers['X-M10V-Seq'],
      headers['X-M10V-Nonce'],
      '$status',
      sha256.convert(raw).toString()
    ].join('\n');
    return CameraResponse(
        statusCode: status,
        headers: {
          'X-M10V-Boot': boot,
          'X-M10V-Session': session,
          'X-M10V-Response-Signature':
              Hmac(sha256, key).convert(utf8.encode(signed)).toString()
        },
        body: raw);
  }
}

void main() {
  test(
      'authenticated busy read retries boundedly and decodes newest camera state',
      () async {
    final wire = BusyWire();
    var waits = 0;
    final client = CompanionClient(
        transport: wire,
        pairingStore: Keys(),
        identity: identity,
        contract: cameraContract,
        busyWait: () async {
          waits++;
        });
    await client.capabilities();
    final state = await client.state();
    expect(state.slots[9]['filmId'], 321);
    expect(waits, 2);
    expect(wire.sequences, ['1', '2', '3']);
  });
  test('busy cannot retry indefinitely or survive invalidation', () async {
    final wire = BusyWire()..busy = 100;
    var waits = 0;
    final client = CompanionClient(
        transport: wire,
        pairingStore: Keys(),
        identity: identity,
        contract: cameraContract,
        busyWait: () async {
          waits++;
        });
    await client.capabilities();
    await expectLater(client.state(), throwsA(isA<CompanionException>()));
    expect(wire.reads, 4);
    expect(waits, 3);
    late CompanionClient changed;
    final second = BusyWire();
    changed = CompanionClient(
        transport: second,
        pairingStore: Keys(),
        identity: identity,
        contract: cameraContract,
        busyWait: () async {
          changed.invalidate();
        });
    await changed.capabilities();
    await expectLater(changed.state(), throwsA(isA<CompanionException>()));
    expect(second.reads, 1);
  });
}
