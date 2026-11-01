import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:gremote/film/store/sync_repository.dart';
import 'package:gremote/camera/companion/companion_sync_controller.dart';
import 'package:gremote/camera/companion/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/companion_client.dart';
import 'package:gremote/camera/companion/companion_transport.dart';
import 'package:gremote/camera/companion/pairing_store.dart';
import 'package:gremote/camera/gateway/camera_transport.dart';

import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/camera/companion/generated_camera_contract.dart';

class _Keys implements PairingStore {
  @override
  Future<void> save(String id, Uint8List key) async {}
  @override
  Future<void> remove(String id) async {}
  @override
  Future<Uint8List> sign(String id, Uint8List bytes) async =>
      Uint8List.fromList(
          Hmac(sha256, List.generate(32, (i) => i)).convert(bytes).bytes);
}

/// Loopback-only fixture. Production uses NativeCompanionTransport exclusively.
class _Loopback implements CompanionTransport {
  _Loopback(this.port);
  final int port;
  final http = HttpClient();
  bool dropNextOperation = false;
  final operationBodies = <String>[];
  final responses = <String>[];
  @override
  Future<CameraResponse> request(
      {required String method,
      required String path,
      required Map<String, String> headers,
      required Uint8List body}) async {
    if (method == 'POST' && path == '/m10v/v1/operations') {
      operationBodies.add(utf8.decode(body));
      if (dropNextOperation) {
        dropNextOperation = false;
        throw TimeoutException('POST never reached server');
      }
    }
    final request = await http.openUrl(
        method, Uri(scheme: 'http', host: '127.0.0.1', port: port, path: path));
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    responses
        .add('$method $path ${response.statusCode}: ${utf8.decode(bytes)}');
    final fields = <String, String>{};
    response.headers.forEach((name, values) => fields[name] = values.join(","));
    return CameraResponse(
        statusCode: response.statusCode,
        headers: fields,
        body: Uint8List.fromList(bytes));
  }
}

void main() {
  final root = Platform.environment['M10V_CURRENT_HOST_ROOT'];
  test(
      'current real C HTTP reads ten slots and installs latest film without duplicates',
      () async {
    final wrapper = await Process.start(
        Platform.environment['M10V_PYTHON'] ?? 'python3',
        [
          '-u',
          '-c',
          r"""
import os,subprocess,sys
from tests.test_companion_server import Server
Server.setUpClass()
env=dict(os.environ,M10V_TEST_CURRENT='1',M10V_TEST_ASYNC_READ='1')
p=subprocess.Popen([str(Server.exe)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
try:
 line=p.stdout.readline()
 if not line:raise RuntimeError(p.stderr.read())
 print(line.strip(),flush=True)
 sys.stdin.buffer.read()
finally:
 p.terminate();p.wait(timeout=3)
 Server.tearDownClass()
"""
        ],
        workingDirectory: root);
    final diagnostics = StringBuffer();
    wrapper.stderr.transform(utf8.decoder).listen(diagnostics.write);
    _Loopback? wire;
    try {
      final port = int.parse(await wrapper.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 30)));
      wire = _Loopback(port);
      final client = CompanionClient(
          transport: wire,
          pairingStore: _Keys(),
          identity: const PairingIdentity(
              instanceId: '01010101010101010101010101010101',
              keyId: 'fixture-key'),
          contract: cameraContract,
          busyWait: () async {});
      final caps = await client.capabilities();
      expect(caps.compatibleWith(cameraCatalogHash, cameraRendererHash), true);
      final before = await client.state();
      expect(before.slots.length, 10);
      expect(before.hasUnknownFields, false);
      final catalog = CameraFilmCatalog.fromJson(jsonDecode(
          File('assets/films/camera-catalog.json').readAsStringSync()));
      sqfliteFfiInit();
      final db = await GRemoteDatabase.open(
          factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final sync = CompanionSyncController(
          api: client,
          repository: SyncRepository(db),
          catalogHash: cameraCatalogHash,
          rendererHash: cameraRendererHash,
          cameraCatalog: catalog,
          wait: () async {});
      try {
        await sync.prepareLoad(
            slot: 9,
            recipe: catalog.recipe(321, parameters: {'grain': 2}),
            activate: true);
        expect(sync.state.readOnly, false);
        await sync.confirm();
        expect(sync.state.operationStatus, SyncOperationStatus.synced,
            reason:
                '${sync.state.message} ${wire.responses.where((r) => r.contains('operations')).join('\n')}');
        final loaded = await client.state();
        expect(loaded.slots[5]['filmId'], 321);
        expect(loaded.slots[5]['parameters'], containsPair('grain', 2));
        expect(loaded.activeSlot, 5);
        expect(loaded.wire['journalSequence'],
            1); // Activation changes tone, not stored configuration.
        expect(wire.operationBodies.length, 2);
        expect(jsonDecode(wire.operationBodies.last)['activateSlot'], 5);
        expect(jsonDecode(wire.operationBodies.last)['patch'], isEmpty);
        await sync.prepareLoad(
            slot: 0,
            recipe: catalog.recipe(321, parameters: {'grain': 3}),
            activate: false);
        expect(sync.preparedSlot, 5);
        await sync.confirm();
        expect(sync.state.operationStatus, SyncOperationStatus.synced,
            reason:
                '${sync.state.message} ${wire.responses.where((r) => r.contains('operations')).join('\n')}');
        final revised = await client.state();
        expect(revised.slots.where((s) => s['filmId'] == 321).length, 1);
        expect(revised.slots[5]['parameters'], containsPair('grain', 3));
        expect(revised.slots.take(5).toList(), before.slots.take(5).toList());
        for (final body in wire.operationBodies) {
          for (final patch in jsonDecode(body)['patch'] as List) {
            expect((patch as Map).keys, isNot(contains('grainSize')));
            expect(patch.keys, isNot(contains('leakGain')));
          }
        }
      } finally {
        sync.dispose();
        await db.close();
      }
    } finally {
      wire?.http.close(force: true);
      await wrapper.stdin.close();
      expect(await wrapper.exitCode.timeout(const Duration(seconds: 5)), 0,
          reason: diagnostics.toString());
    }
  },
      skip: root == null
          ? 'Set M10V_CURRENT_HOST_ROOT for current C loopback integration'
          : false,
      timeout: const Timeout(Duration(seconds: 60)));
}
