import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:gremote/film/store/sync_repository.dart';
import 'package:gremote/film/model/film_recipe.dart';
import 'package:gremote/camera/companion/companion_sync_controller.dart';
import 'package:gremote/camera/companion/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/companion_client.dart';
import 'package:gremote/camera/companion/companion_protocol.dart';
import 'package:gremote/camera/companion/companion_transport.dart';
import 'package:gremote/camera/companion/pairing_store.dart';
import 'package:gremote/camera/gateway/camera_transport.dart';

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
  @override
  Future<CameraResponse> request(
      {required String method,
      required String path,
      required Map<String, String> headers,
      required Uint8List body}) async {
    final request = await http.openUrl(
        method, Uri(scheme: 'http', host: '127.0.0.1', port: port, path: path));
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    final fields = <String, String>{};
    response.headers.forEach((name, values) => fields[name] = values.join(","));
    return CameraResponse(
        statusCode: response.statusCode,
        headers: fields,
        body: Uint8List.fromList(bytes));
  }
}

void main() {
  final root = Platform.environment['M10V_HOST_ROOT'];
  test(
      'real C HTTP: authenticated state, resumed upload, verified data then one journal install',
      () async {
    final python = Platform.environment['M10V_PYTHON'] ?? 'python3';
    final wrapper = await Process.start(
        python,
        [
          '-u',
          '-c',
          r'''
import os,subprocess,sys
from tests.test_companion_server import Server
Server.setUpClass()
env=dict(os.environ,M10V_TEST_UPLOAD='1')
p=subprocess.Popen([str(Server.exe)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
try:
 line=p.stdout.readline()
 if not line:raise RuntimeError(p.stderr.read())
 print(line.strip(),flush=True)
 sys.stdin.buffer.read()
finally:
 p.terminate();p.wait(timeout=3)
 Server.tearDownClass()
'''
        ],
        workingDirectory: root);
    final diagnostics = StringBuffer();
    wrapper.stderr.transform(utf8.decoder).listen(diagnostics.write);
    final port = int.parse(await wrapper.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 30)));
    final wire = _Loopback(port);
    try {
      final client = CompanionClient(
          transport: wire,
          pairingStore: _Keys(),
          identity: const PairingIdentity(
              instanceId: '01010101010101010101010101010101',
              keyId: 'fixture-key'));
      final caps = await client.capabilities();
      expect(caps.supports('uploadFilm'), isTrue);
      final before = await client.state();
      final recordResult = await Process.run(
          'node',
          [
            '--input-type=module',
            '-e',
            "import{customFilmRecord}from'./node/gr3-sd-film-pack.mjs';process.stdout.write(customFilmRecord({name:'DART',rgb:Buffer.alloc(6591,128)},79));"
          ],
          workingDirectory: root,
          stdoutEncoding: null);
      expect(recordResult.exitCode, 0);
      final record = Uint8List.fromList(recordResult.stdout as List<int>),
          hash = sha256.convert(record).toString();
      final metadata = FilmUploadMetadata(
          stableId: 79,
          targetSlot: 3,
          rendererHash: caps.rendererHash,
          contentHash: hash);
      final stage = await client.stageFilm(metadata);
      expect(stage.receivedBytes, 0);
      final chunk = Uint8List.sublistView(record, 0, 4096);
      expect(
          (await client.sendFilmChunk(stage.uploadId, 0, chunk)).receivedBytes,
          4096);
      expect(
          (await client.sendFilmChunk(stage.uploadId, 0, chunk)).receivedBytes,
          4096);
      final resumed = await client.stageFilm(metadata);
      expect(resumed.uploadId, stage.uploadId);
      expect(resumed.receivedBytes, 4096);
      for (var i = 1; i < 3; i++) {
        await client.sendFilmChunk(stage.uploadId, i,
            Uint8List.sublistView(record, i * 4096, (i + 1) * 4096));
      }
      expect((await client.verifyFilm(stage.uploadId)).status, 'verified');
      expect((await client.state()).revision, before.revision);
      final payload = <String, Object?>{
        'protocol': 1,
        'requestId': 'aa' * 16,
        'bootId': before.bootId,
        'baseRevision': before.revision,
        'catalogHash': caps.catalogHash,
        'rendererHash': caps.rendererHash,
        'patch': [
          {'slot': 3, 'filmId': 79, 'customHash': hash}
        ],
        'activateSlot': null
      };
      expect((await client.submit(payload)).status,
          CompanionOperationStatus.queued);
      CompanionOperationReceipt receipt = await client.operation('aa' * 16);
      for (var i = 0;
          i < 5 && receipt.status != CompanionOperationStatus.committed;
          i++) {
        receipt = await client.operation('aa' * 16);
      }
      expect(receipt.status, CompanionOperationStatus.committed);
      expect(receipt.snapshot!.wire['journalSequence'], 1);
      expect(receipt.snapshot!.slots[3]['customHash'], hash);
      expect(receipt.snapshot!.activeSlot, before.activeSlot);
      expect(
          (await client.submit(payload)).snapshot!.wire['journalSequence'], 1);

      sqfliteFfiInit();
      final db = await GRemoteDatabase.open(
          factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final sync = CompanionSyncController(
          api: client,
          repository: SyncRepository(db),
          catalogHash: caps.catalogHash,
          rendererHash: caps.rendererHash,
          wait: () async {});
      try {
        final current = await client.state();
        final original = current.recipeAt(0);
        final target = FilmRecipe.fromJson({
          ...original.toJson(),
          'parameters': {...original.parameters, 'grain': 2}
        });
        await sync.prepareLoad(slot: 0, recipe: target, activate: false);
        expect(sync.state.readOnly, isFalse);
        await sync.confirm();
        expect(sync.state.operationStatus, SyncOperationStatus.synced);
        expect(sync.state.snapshot!.wire['journalSequence'], 2);
      } finally {
        sync.dispose();
        await db.close();
      }
    } finally {
      wire.http.close(force: true);
      await wrapper.stdin.close();
      expect(await wrapper.exitCode.timeout(const Duration(seconds: 5)), 0,
          reason: diagnostics.toString());
    }
  },
      skip: root == null
          ? 'Set M10V_HOST_ROOT for explicit real C loopback integration'
          : false,
      timeout: const Timeout(Duration(seconds: 60)));
}
