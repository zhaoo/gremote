import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/companion_client.dart';
import 'package:gremote/camera/companion/companion_transport.dart';
import 'package:gremote/camera/companion/companion_protocol.dart';
import 'package:gremote/camera/companion/generated_contract.dart';
import 'package:gremote/camera/companion/pairing_store.dart';
import 'package:gremote/camera/gateway/camera_transport.dart';
import 'package:gremote/camera/http/camera_files.dart';

final contract = jsonDecode(companionContractJson) as Map<String, dynamic>;
final key = Uint8List.fromList(List.generate(32, (i) => i));
final identity = PairingIdentity(instanceId: '01' * 16, keyId: 'fixture-key');
Map<String, dynamic> capabilities() => {
      'protocol': 1,
      'model': 'GR III',
      'recipeSchema': 1,
      'slotCount': 5,
      'firmwareIdentity': contract['officialFirmwareSha256'],
      'bootId': '02' * 16,
      'sessionId': '03' * 16,
      'instanceId': identity.instanceId,
      'buildId': '04' * 32,
      'catalogHash': '05' * 32,
      'rendererHash': '06' * 32,
      'capabilities': {
        'readState': true,
        'writeState': false,
        'uploadFilm': false,
        'captureEvidence': false
      },
      'parameters': contract['parameters'],
      'limits': contract['limits']
    };

class Keys implements PairingStore {
  Uint8List? saved, borrowed;
  @override
  Future<void> save(String id, Uint8List bytes) async {
    borrowed = bytes;
    saved = Uint8List.fromList(bytes);
  }

  @override
  Future<void> remove(String id) async {}
  @override
  Future<Uint8List> sign(String id, Uint8List bytes) async =>
      Uint8List.fromList(Hmac(sha256, key).convert(bytes).bytes);
}

class Wire implements CompanionTransport {
  bool tamper = false, changedBoot = false;
  int count = 0;
  final paths = <String>[];
  final replies = <String, (int, Map<String, Object?>)>{};
  @override
  Future<CameraResponse> request(
      {required String method,
      required String path,
      required Map<String, String> headers,
      required Uint8List body}) async {
    count++;
    paths.add(path);
    expect(headers['X-M10V-KeyId'], identity.keyId);
    final canonical = [
      method,
      path,
      headers['X-M10V-Boot'],
      headers['X-M10V-Session'],
      headers['X-M10V-Seq'],
      headers['X-M10V-Nonce'],
      sha256.convert(body).toString()
    ].join('\n');
    expect(headers['X-M10V-Signature'],
        Hmac(sha256, key).convert(utf8.encode(canonical)).toString());
    final (status, payload) = replies[path] ?? (200, capabilities());
    final raw = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final boot = changedBoot ? '09' * 16 : '02' * 16, session = '03' * 16;
    final response = [
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
          'X-M10V-Response-Signature': tamper
              ? '00' * 32
              : Hmac(sha256, key).convert(utf8.encode(response)).toString()
        },
        body: raw);
  }
}

void main() {
  test('IIIx uses its own official firmware identity and pairing model',
      () async {
    final value = capabilities()
      ..['model'] = 'GR IIIx'
      ..['firmwareIdentity'] =
          '708e79f3b7b96a7e1581b4acf4c412233050a1832718ef7f06c8397db1b431c7';
    expect(
        CompanionCapabilities.fromJson(value)
            .compatibleWith('05' * 32, '06' * 32),
        isTrue);
    value['firmwareIdentity'] = contract['officialFirmwareSha256'];
    expect(
        CompanionCapabilities.fromJson(value)
            .compatibleWith('05' * 32, '06' * 32),
        isFalse);
    final file = {
      'schema': 'm10v.companion-pairing/v1',
      'protocol': 1,
      'model': 'GR IIIx',
      'instanceId': '01' * 16,
      'keyId': sha256.convert(key).toString().substring(0, 32),
      'keyHex': key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()
    };
    expect(
        (await importPairing(
                Uint8List.fromList(utf8.encode(jsonEncode(file))), Keys()))
            .instanceId,
        '01' * 16);
  });

  test(
      'signed M10V capabilities cannot impersonate a different connected model',
      () async {
    final client = CompanionClient(
        transport: Wire(),
        pairingStore: Keys(),
        identity: identity,
        expectedModel: 'GR IIIx');
    await expectLater(
        client.capabilities(), throwsA(isA<CompanionException>()));
    expect(client.bootId, isNull);
  });
  test('Live uses signed exact DCF routes and distinguishes a signed 404',
      () async {
    const photo = CameraFile(dir: '100RICOH', file: 'R0000021.JPG');
    const path = '/m10v/v1/live/100RICOH/R0000021/JPG';
    final clip = Uint8List.fromList(List.generate(48, (i) => i));
    final wire = Wire()
      ..replies[path] = (
        200,
        {
          'version': 1,
          'jpeg': {
            'directory': photo.dir,
            'file': photo.file,
            'sha256': 'ab' * 32
          },
          'clip': {
            'directory': 'LIVE',
            'file': 'clip.m10l',
            'format': 'm10l',
            'sha256': sha256.convert(clip).toString(),
            'bytes': 48,
          },
          'presentationTimestampUs': 120000,
        }
      )
      ..replies['$path/clip/0'] = (
        200,
        {
          'offset': 0,
          'bytes': 48,
          'data': base64Encode(clip.sublist(0, 17)),
        }
      )
      ..replies['$path/clip/17'] = (
        200,
        {
          'offset': 17,
          'bytes': 48,
          'data': base64Encode(clip.sublist(17)),
        }
      );
    final client = CompanionClient(
        transport: wire, pairingStore: Keys(), identity: identity);
    final pair = (await client.liveManifest(photo))!;
    final downloaded = <int>[];
    await client.liveClip(pair, (chunk) async => downloaded.addAll(chunk));
    expect(downloaded, clip);
    expect(wire.paths, [
      '/m10v/v1/capabilities',
      path,
      '$path/clip/0',
      '$path/clip/17',
    ]);
    wire.replies[path] = (
      404,
      {
        'error': {'code': 'missing'}
      }
    );
    expect(await client.liveManifest(photo), isNull);
    wire.tamper = true;
    await expectLater(
        client.liveManifest(photo), throwsA(isA<CompanionException>()));
  });

  test('request and response canonical HMAC match independent oracle',
      () async {
    final wire = Wire();
    final client = CompanionClient(
        transport: wire, pairingStore: Keys(), identity: identity);
    final caps = await client.capabilities();
    expect(caps.bootId, '02' * 16);
    expect(client.bootId, caps.bootId);
    expect(caps.compatibleWith('05' * 32, '06' * 32), isTrue);
  });
  test('unsigned or tampered response cannot establish session', () async {
    final wire = Wire()..tamper = true;
    final client = CompanionClient(
        transport: wire, pairingStore: Keys(), identity: identity);
    await expectLater(
        client.capabilities(), throwsA(isA<CompanionException>()));
    expect(client.bootId, isNull);
  });
  test('signed bootstrap must bind body identity and returned boot', () async {
    final wire = Wire()..changedBoot = true;
    final client = CompanionClient(
        transport: wire, pairingStore: Keys(), identity: identity);
    await expectLater(
        client.capabilities(), throwsA(isA<CompanionException>()));
    expect(client.bootId, isNull);
  });
  test('unknown capability fields survive and force read-only compatibility',
      () {
    final value = capabilities()..['newCapability'] = {'private': 7};
    final caps = CompanionCapabilities.fromJson(value);
    expect(caps.wire['newCapability'], {'private': 7});
    expect(caps.compatibleWith('05' * 32, '06' * 32), isFalse);
    expect(() => (caps.wire['newCapability'] as Map)['private'] = 8,
        throwsUnsupportedError);
  });
  test('pairing import validates key identity and wipes temporary key',
      () async {
    final store = Keys();
    final file = {
      'schema': 'm10v.companion-pairing/v1',
      'protocol': 1,
      'model': 'GR III',
      'instanceId': '01' * 16,
      'keyId': sha256.convert(key).toString().substring(0, 32),
      'keyHex': key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()
    };
    final pairing = await importPairing(
        Uint8List.fromList(utf8.encode(jsonEncode(file))), store);
    expect(pairing.instanceId, '01' * 16);
    expect(store.saved, key);
    expect(store.borrowed, everyElement(0));
    file['keyId'] = '00' * 16;
    await expectLater(
        importPairing(Uint8List.fromList(utf8.encode(jsonEncode(file))), store),
        throwsFormatException);
  });
}
