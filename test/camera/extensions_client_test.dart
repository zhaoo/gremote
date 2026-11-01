import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/companion_client.dart';
import 'package:gremote/camera/companion/companion_transport.dart';
import 'package:gremote/camera/companion/extensions_protocol.dart';
import 'package:gremote/camera/gateway/camera_transport.dart';

import 'companion_client_test.dart' show Keys, capabilities, identity, key;

const _hash =
    '9df047418574e23fd399a0c59491aecc9ea212dbf119a79ff29532aec6493628';
// Independent remote fixture: stable v1 fields/ranges/persistence, not generated
// from the app's field table or parser implementation.
const _ranges = <String, List<int>>{
  'quickSwitch': [0, 1],
  'quickSwitchA': [0, 21],
  'quickSwitchB': [0, 21],
  'hdf': [0, 3],
  'border': [0, 2],
  'grainMode': [0, 4],
  'grainSize': [0, 2],
  'leakGain': [0, 3],
  'leakPosition': [0, 2],
  'leakSpread': [0, 2],
  'blurGain': [0, 3],
  'blurRange': [0, 2],
  'stamp': [0, 2],
  'stampFormat': [0, 3],
  'stampCorner': [0, 3],
  'stampColor': [0, 3],
  'filmNameStamp': [0, 1],
  'focalA': [28, 50],
  'focalB': [28, 50],
  'focalSlot': [0, 2],
  'aspect': [0, 6],
};

Map<String, dynamic> _caps() => {
      'schema': 'm10v.extensions/v1',
      'contractHash': _hash,
      'fields': [
        for (final e in _ranges.entries)
          {
            'key': e.key,
            'min': e.value[0],
            'max': e.value[1],
            'supported': true,
            'persistence':
                {'quickSwitch', 'focalSlot', 'aspect'}.contains(e.key)
                    ? 'runtime'
                    : 'persistent'
          },
      ],
      'powerImages': {'supported': false, 'reason': 'firmwareBuildRequired'},
    };

Map<String, dynamic> _state() => {
      'schema': 'm10v.extensions/v1',
      'contractHash': _hash,
      'instanceId': identity.instanceId,
      'buildId': '04' * 32,
      'bootId': '02' * 16,
      'revision': '07' * 32,
      'busy': false,
      'supported': _ranges.keys.toList(),
      'values': {for (final e in _ranges.entries) e.key: e.value[0]},
    };

class _Call {
  _Call(this.method, this.path, this.headers, this.body);
  final String method, path;
  final Map<String, String> headers;
  final Uint8List body;
}

class _SignedWire implements CompanionTransport {
  final calls = <_Call>[];
  final state = _state();
  String? failPath, errorCode, responseBoot;
  int failureStatus = 404, busyReads = 0;
  bool tamper = false, unsigned = false;
  Map<String, dynamic> Function(String, Map<String, dynamic>)? transform;
  String _lastId = 'aa' * 16;

  @override
  Future<CameraResponse> request(
      {required String method,
      required String path,
      required Map<String, String> headers,
      required Uint8List body}) async {
    calls.add(_Call(method, path, Map.of(headers), Uint8List.fromList(body)));
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
    final extension = path.startsWith('/m10v/v1/extensions/');
    var status = 200;
    Map<String, dynamic> payload;
    if (path == '/m10v/v1/capabilities') {
      expect(method, 'GET');
      expect(body, isEmpty);
      expect(headers['X-M10V-Boot'], '');
      expect(headers['X-M10V-Session'], '');
      expect(headers['X-M10V-Seq'], '0');
      payload = capabilities();
    } else {
      expect(headers['X-M10V-Boot'], '02' * 16);
      expect(headers['X-M10V-Session'], '03' * 16);
      if (path == failPath) {
        status = failureStatus;
        payload = {
          'error': {'code': errorCode ?? 'invalidRecipe'}
        };
      } else if (busyReads > 0 && path.endsWith('/state')) {
        busyReads--;
        status = 503;
        payload = {
          'error': {'code': 'busy'}
        };
      } else if (path.endsWith('/capabilities')) {
        payload = _caps();
      } else if (path.endsWith('/state')) {
        payload = state;
      } else if (method == 'POST') {
        final operation = jsonDecode(utf8.decode(body)) as Map;
        _lastId = operation['requestId'] as String;
        (state['values'] as Map)[operation['field']] = operation['value'];
        state['revision'] = '08' * 32;
        status = 202;
        payload = {
          'requestId': _lastId,
          'bootId': '02' * 16,
          'status': 'queued'
        };
      } else {
        payload = {
          'requestId': _lastId,
          'bootId': '02' * 16,
          'status': 'committed',
          'snapshot': state
        };
      }
    }
    if (extension && transform != null) payload = transform!(path, payload);
    final raw = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final boot = extension ? responseBoot ?? '02' * 16 : '02' * 16;
    final canonicalResponse = [
      'RESPONSE',
      method,
      path,
      boot,
      '03' * 16,
      headers['X-M10V-Seq'],
      headers['X-M10V-Nonce'],
      '$status',
      sha256.convert(raw).toString()
    ].join('\n');
    return CameraResponse(
        statusCode: status,
        headers: {
          'X-M10V-Boot': boot,
          'X-M10V-Session': '03' * 16,
          if (!(extension && unsigned))
            'X-M10V-Response-Signature': extension && tamper
                ? '00' * 32
                : Hmac(sha256, key)
                    .convert(utf8.encode(canonicalResponse))
                    .toString(),
        },
        body: raw);
  }
}

CompanionClient _client(_SignedWire wire, {Future<void> Function()? wait}) =>
    CompanionClient(
        transport: wire,
        pairingStore: Keys(),
        identity: identity,
        busyWait: wait);
Matcher _error(String code) =>
    throwsA(isA<CompanionException>().having((e) => e.code, 'code', code));

void main() {
  test('legacy bootstrap and signed extension requests share one HMAC session',
      () async {
    final wire = _SignedWire();
    final actual = _client(wire);
    expect(actual, isA<CompanionExtensionsApi>());
    final legacy = await actual.capabilities();
    expect(legacy.compatibleWith('05' * 32, '06' * 32), isTrue);
    expect(legacy.wire.containsKey('extensions'), isFalse);
    expect(
        (await actual.extensionCapabilities()).supported, _ranges.keys.toSet());
    final state = await actual.extensionState();
    expect(state.values['focalA'], 28);
    final operation = <String, Object?>{
      'requestId': 'aa' * 16,
      'bootId': state.bootId,
      'contractHash': _hash,
      'baseRevision': state.revision,
      'field': 'aspect',
      'value': 6
    };
    expect((await actual.submitExtension(operation)).status, 'queued');
    expect(
        (await actual.extensionOperation('aa' * 16)).snapshot!.values['aspect'],
        6);
    expect(wire.calls.map((c) => c.headers['X-M10V-Seq']),
        ['0', '1', '2', '3', '4']);
    expect(wire.calls.map((c) => c.headers['X-M10V-Nonce']).toSet().length, 5);
    expect(jsonDecode(utf8.decode(wire.calls[3].body)), operation);
    expect(wire.calls.map((c) => c.path), [
      '/m10v/v1/capabilities',
      '/m10v/v1/extensions/capabilities',
      '/m10v/v1/extensions/state',
      '/m10v/v1/extensions/operations',
      '/m10v/v1/extensions/operations/${'aa' * 16}'
    ]);
  });

  test(
      'extension API cannot bootstrap or send requests without pairing session',
      () async {
    final wire = _SignedWire();
    final actual = _client(wire);
    await expectLater(actual.extensionCapabilities(), _error('notPaired'));
    await expectLater(actual.extensionState(), _error('notPaired'));
    expect(wire.calls, isEmpty);
  });

  test('only authenticated legacy 404 discovery maps to extensionsUnsupported',
      () async {
    final wire = _SignedWire()..failPath = '/m10v/v1/extensions/capabilities';
    final client = _client(wire);
    await client.capabilities();
    await expectLater(
        client.extensionCapabilities(), _error('extensionsUnsupported'));
    expect(client.bootId, '02' * 16);
    wire.failPath = '/m10v/v1/extensions/state';
    wire.errorCode = 'resultUnknown';
    await expectLater(client.extensionState(), _error('resultUnknown'));
    wire.failPath = '/m10v/v1/extensions/operations/${'aa' * 16}';
    await expectLater(
        client.extensionOperation('aa' * 16), _error('resultUnknown'));
    wire.failPath = '/m10v/v1/extensions/capabilities';
    wire.failureStatus = 503;
    wire.errorCode = 'bridgeUnavailable';
    await expectLater(
        client.extensionCapabilities(), _error('bridgeUnavailable'));
  });

  test('unsigned and tampered discovery responses including 404 stay untrusted',
      () async {
    for (final unsigned in [false, true]) {
      final wire = _SignedWire()..failPath = '/m10v/v1/extensions/capabilities';
      final client = _client(wire);
      await client.capabilities();
      wire.unsigned = unsigned;
      wire.tamper = !unsigned;
      await expectLater(
          client.extensionCapabilities(), _error('unauthenticatedResponse'));
    }
  });

  test('signed session boot change invalidates session before decoding state',
      () async {
    final wire = _SignedWire();
    final actual = _client(wire);
    await actual.capabilities();
    wire.responseBoot = '09' * 16;
    await expectLater(actual.extensionState(), _error('sessionChanged'));
    expect(actual.bootId, isNull);
  });

  test('authenticated body identities must match paired instance and boot',
      () async {
    for (final field in ['bootId', 'instanceId', 'buildId']) {
      final wire = _SignedWire();
      final client = _client(wire);
      await client.capabilities();
      wire.transform =
          (path, v) => {...v, field: '09' * (field == 'buildId' ? 32 : 16)};
      await expectLater(client.extensionState(), _error('identityMismatch'));
    }
  });

  test('malformed authenticated capabilities and values cannot enable writes',
      () async {
    final transforms = <Map<String, dynamic> Function(Map<String, dynamic>)>[
      (v) => {...v, 'contractHash': 'ff' * 32},
      (v) => {...v, 'fields': (v['fields'] as List).sublist(1)},
    ];
    for (final transform in transforms) {
      final wire = _SignedWire();
      final client = _client(wire);
      await client.capabilities();
      wire.transform = (path, v) => transform(v);
      await expectLater(client.extensionCapabilities(), throwsFormatException);
    }
    final wire = _SignedWire();
    final client = _client(wire);
    await client.capabilities();
    wire.transform = (path, v) => {
          ...v,
          'values': {...v['values'] as Map, 'hdf': 4}
        };
    await expectLater(client.extensionState(), throwsFormatException);
  });

  test('receipt IDs boot IDs and nested snapshot identities are bound',
      () async {
    final changes = <Map<String, dynamic> Function(Map<String, dynamic>)>[
      (v) => {...v, 'requestId': 'bb' * 16},
      (v) => {...v, 'bootId': '09' * 16},
      (v) => {
            ...v,
            'snapshot': {...v['snapshot'] as Map, 'instanceId': '09' * 16}
          },
    ];
    for (final change in changes) {
      final wire = _SignedWire();
      final client = _client(wire);
      await client.capabilities();
      wire.transform = (path, v) => change(v);
      await expectLater(
          client.extensionOperation('aa' * 16), _error('identityMismatch'));
    }
  });

  test(
      'committed without verified snapshot is malformed; rejection code survives',
      () async {
    final wire = _SignedWire();
    final client = _client(wire);
    await client.capabilities();
    wire.transform = (path, v) => {...v, 'snapshot': null};
    await expectLater(
        client.extensionOperation('aa' * 16), throwsFormatException);
    wire.transform = (path, v) => {
          'requestId': 'aa' * 16,
          'bootId': '02' * 16,
          'status': 'rejected',
          'code': 'revisionConflict'
        };
    final receipt = await client.extensionOperation('aa' * 16);
    expect(receipt.status, 'rejected');
    expect(receipt.code, 'revisionConflict');
  });

  test('request ID path injection is rejected before transport or signing',
      () async {
    final wire = _SignedWire();
    final client = _client(wire);
    await client.capabilities();
    for (final id in [
      '../state',
      'https://other/',
      '${'aa' * 16}?x=1',
      '${'aa' * 16}/extra'
    ]) {
      await expectLater(
          client.extensionOperation(id), _error('invalidCompanionTarget'));
    }
    expect(wire.calls.length, 1);
  });

  test('busy reads retry boundedly with new signed sequences and never submit',
      () async {
    final wire = _SignedWire()..busyReads = 2;
    var waits = 0;
    final client = _client(wire, wait: () async {
      waits++;
    });
    await client.capabilities();
    expect((await client.extensionState()).values['hdf'], 0);
    expect(waits, 2);
    expect(
        wire.calls.map((c) => c.headers['X-M10V-Seq']), ['0', '1', '2', '3']);
    expect(wire.calls.every((c) => c.method == 'GET'), isTrue);
  });
}
