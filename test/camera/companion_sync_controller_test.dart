import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:gremote/camera/companion/film_transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:gremote/film/store/sync_repository.dart';
import 'package:gremote/film/model/film_recipe.dart';
import 'package:gremote/camera/companion/companion_client.dart';
import 'package:gremote/camera/companion/companion_protocol.dart';
import 'package:gremote/camera/companion/companion_sync_controller.dart';
import 'package:gremote/camera/companion/sync_state.dart';
import 'three_way_merge_test.dart' show config;
import 'companion_client_test.dart' as fixture;

class FakeCompanion implements CompanionApi {
  Map<String, dynamic> caps = fixture.capabilities();
  Map<String, Object?> current = config();
  String boot = '02' * 16;
  int sequence = 0, stateReads = 0;
  int? active = 0;
  bool lost = false,
      unknown = false,
      rejectActivation = false,
      mismatch = false;
  Completer<void>? waitRead;
  bool lostVerify = false;
  Map<String, Object?>? uploadMeta;
  int uploaded = 0, verifyCalls = 0;
  bool uploadVerified = false;
  final operations = <Map<String, Object?>>[];
  bool commitInSubmit = false;
  void Function()? onSubmit;
  FakeCompanion() {
    (caps['capabilities'] as Map)['writeState'] = true;
  }
  @override
  String? get bootId => boot;
  CompanionSnapshot snapshot() => CompanionSnapshot.fromJson({
        'protocol': 1,
        'schemaVersion': 1,
        'bootId': boot,
        'instanceId': caps['instanceId'],
        'catalogHash': caps['catalogHash'],
        'rendererHash': caps['rendererHash'],
        'revision': sequence.toRadixString(16).padLeft(64, '0'),
        'configHash': sequence.toRadixString(16).padLeft(64, '0'),
        'journalSequence': sequence,
        'activeSlot': active,
        'busy': false,
        'fresh': true,
        'config': current
      });
  @override
  Future<CompanionCapabilities> capabilities() async =>
      CompanionCapabilities.fromJson({...caps, 'bootId': boot});
  @override
  Future<CompanionSnapshot> state() async {
    stateReads++;
    await waitRead?.future;
    return snapshot();
  }

  @override
  void invalidate() {}
  @override
  Future<CompanionOperationReceipt> submit(Map<String, Object?> value) async {
    operations.add(value);
    if (lost) throw TimeoutException('fixture');
    if (commitInSubmit) {
      final result = await operation(value['requestId'] as String);
      onSubmit?.call();
      return result;
    }
    return receipt(value, 'queued');
  }

  CompanionOperationReceipt receipt(
          Map<String, Object?> value, String status) =>
      CompanionOperationReceipt.fromJson({
        'requestId': value['requestId'],
        'bootId': boot,
        'status': status,
        if (status == 'committed') 'snapshot': snapshot().wire,
        if (status == 'rejected') 'error': {'code': 'busy'}
      });
  @override
  Future<CompanionOperationReceipt> operation(String id) async {
    final value = operations.singleWhere((o) => o['requestId'] == id);
    if (unknown) return receipt(value, 'unknown');
    if (rejectActivation && value['activateSlot'] != null) {
      return receipt(value, 'rejected');
    }
    if (!mismatch) {
      current =
          Map<String, Object?>.from(jsonDecode(jsonEncode(current)) as Map);
      for (final raw in value['patch'] as List) {
        final patch = Map<String, Object?>.from(raw as Map),
            slot = patch.remove('slot') as int;
        final target = (current['slots'] as List)[slot] as Map;
        for (final e in patch.entries) {
          if (e.key == 'filmId' || e.key == 'customHash') {
            target[e.key] = e.value;
          } else {
            (target['parameters'] as Map)[e.key] = e.value;
          }
        }
      }
      if ((value['patch'] as List).isNotEmpty) sequence++;
      if (value['activateSlot'] != null) active = value['activateSlot'] as int;
    }
    return receipt(value, 'committed');
  }

  FilmUploadReceipt uploadReceipt(String status) => FilmUploadReceipt.fromJson({
        ...uploadMeta!,
        'uploadId': 'ee' * 16,
        'receivedBytes': uploaded,
        'status': status,
        if (status == 'verified') 'bank': 1
      });
  @override
  Future<FilmUploadReceipt> stageFilm(FilmUploadMetadata metadata) async {
    uploadMeta = metadata.toJson();
    return uploadReceipt('receiving');
  }

  @override
  Future<FilmUploadReceipt> sendFilmChunk(
      String id, int index, Uint8List bytes) async {
    uploaded += bytes.length;
    return uploadReceipt('receiving');
  }

  @override
  Future<FilmUploadReceipt> filmUpload(String id) async =>
      uploadReceipt(uploadVerified ? 'verified' : 'receiving');
  @override
  Future<FilmUploadReceipt> verifyFilm(String id) async {
    verifyCalls++;
    uploadVerified = true;
    if (lostVerify) throw TimeoutException('fixture');
    return uploadReceipt('verified');
  }
}

FilmRecipe recipe() => FilmRecipe.fromJson({
      'schemaVersion': 1,
      'filmId': 33,
      'catalogHash': '05' * 32,
      'rendererHash': '06' * 32,
      'parameters': {'grain': 2, 'grainSize': 1},
      'name': 'TEST'
    });
void main() {
  sqfliteFfiInit();
  late Database db;
  late FakeCompanion api;
  late CompanionSyncController controller;
  late SyncRepository repository;
  var blocked = false;
  setUp(() async {
    db = await GRemoteDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    api = FakeCompanion();
    repository = SyncRepository(db);
    blocked = false;
    controller = CompanionSyncController(
        api: api,
        repository: repository,
        catalogHash: '05' * 32,
        rendererHash: '06' * 32,
        isWriteBlocked: () => blocked,
        wait: () async {});
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });
  test('lost_ack_remains_unknown_until_readback', () async {
    await controller.prepareLoad(slot: 0, recipe: recipe(), activate: false);
    api.lost = true;
    await controller.confirm();
    expect(controller.state.operationStatus, SyncOperationStatus.unknown);
    expect((await repository.unresolved(api.caps['instanceId'] as String)),
        hasLength(1));
    api.lost = false;
    api.unknown = true;
    await controller.reconcileUnknown();
    expect(controller.state.operationStatus, SyncOperationStatus.unknown);
    api.unknown = false;
    await controller.reconcileUnknown();
    expect(controller.state.operationStatus, SyncOperationStatus.synced);
    expect(api.operations, hasLength(1));
  });
  test('committed receipt with mismatching fresh state is not synced',
      () async {
    await controller.prepareLoad(slot: 0, recipe: recipe(), activate: false);
    api.mismatch = true;
    await controller.confirm();
    expect(controller.state.operationStatus, SyncOperationStatus.unknown);
  });
  test(
      'install and activation use separate operations; failed activation preserves install',
      () async {
    await controller.prepareLoad(slot: 3, recipe: recipe(), activate: true);
    api.rejectActivation = true;
    await controller.confirm();
    expect(api.operations, hasLength(2));
    expect(api.operations[0]['activateSlot'], isNull);
    expect(api.operations[1]['patch'], isEmpty);
    expect(controller.state.message, '已装入，切换失败');
    expect(api.active, 0);
    expect((api.current['slots'] as List)[3]['parameters']['grain'], 2);
  });
  test('busy external capture or download defers all writes', () async {
    await controller.prepareLoad(slot: 0, recipe: recipe(), activate: false);
    blocked = true;
    await controller.confirm();
    expect(api.operations, isEmpty);
    expect(controller.state.connectionStatus, SyncConnectionStatus.busy);
    blocked = false;
    await controller.confirm();
    expect(controller.state.operationStatus, SyncOperationStatus.synced);
  });
  test('reboot never automatically replays unresolved request', () async {
    await controller.prepareLoad(slot: 0, recipe: recipe(), activate: false);
    api.lost = true;
    await controller.confirm();
    api.boot = '09' * 16;
    await controller.refresh();
    await controller.reconcileUnknown();
    expect(api.operations, hasLength(1));
    expect(controller.state.operationStatus, SyncOperationStatus.unknown);
    expect(controller.state.rebootNeedsConfirmation, isTrue);
  });
  test('queued or applying status alone is never synchronized', () async {
    await controller.prepareLoad(slot: 0, recipe: recipe(), activate: false);
    api.unknown = true;
    await controller.confirm();
    expect(controller.state.operationStatus, SyncOperationStatus.unknown);
    expect(
        await repository.baseline(api.caps['instanceId'] as String), isNotNull);
  });
  test('background refresh keeps a fresh camera ready while reading', () async {
    await controller.refresh();
    expect(controller.state.connectionStatus, SyncConnectionStatus.ready);
    api.waitRead = Completer<void>();
    final pending = controller.refresh();
    expect(controller.state.connectionStatus, SyncConnectionStatus.ready);
    api.waitRead!.complete();
    await pending;
    expect(controller.state.connectionStatus, SyncConnectionStatus.ready);
  });

  test('dispose suppresses in-flight refresh and all later writes', () async {
    api.waitRead = Completer<void>();
    final pending = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    api.waitRead!.complete();
    await pending;
    expect(api.operations, isEmpty);
  });
  test('unknown remote field stays read-only', () async {
    api.current['newSetting'] = 7;
    await controller.refresh();
    expect(controller.state.readOnly, isTrue);
    await expectLater(
        controller.prepareLoad(slot: 0, recipe: recipe(), activate: false),
        throwsA(isA<CompanionException>()));
    expect(api.operations, isEmpty);
  });
  test('restored unresolved journal blocks new operation until reconciled',
      () async {
    await controller.prepareLoad(slot: 0, recipe: recipe(), activate: false);
    api.lost = true;
    await controller.confirm();
    controller.dispose();
    controller = CompanionSyncController(
        api: api,
        repository: repository,
        catalogHash: '05' * 32,
        rendererHash: '06' * 32,
        wait: () async {});
    await controller.refresh();
    expect(controller.state.operationStatus, SyncOperationStatus.unknown);
    await controller.confirm();
    expect(api.operations, hasLength(1));
  });
  test(
      'lost upload verification persists unknown and recovers read-only before installation',
      () async {
    final bytes = File('test/fixtures/custom-film.m10vfilm').readAsBytesSync();
    final metadata = (jsonDecode(utf8.decode(bytes)) as Map)['metadata'] as Map;
    final renderer = metadata['rendererHash'] as String;
    final film = FilmTransfer.parse(bytes, expectedRenderer: renderer);
    api.caps['rendererHash'] = renderer;
    (api.caps['capabilities'] as Map)['uploadFilm'] = true;
    controller.dispose();
    controller = CompanionSyncController(
        api: api,
        repository: repository,
        catalogHash: '05' * 32,
        rendererHash: renderer,
        wait: () async {});
    await controller.prepareLoad(
        slot: 2, recipe: film.recipe('05' * 32), activate: false, film: film);
    api.lostVerify = true;
    await controller.confirm();
    expect(controller.state.operationStatus, SyncOperationStatus.unknown);
    expect(api.operations, isEmpty);
    expect(await repository.unresolved(api.caps['instanceId'] as String),
        hasLength(1));
    controller.dispose();
    controller = CompanionSyncController(
        api: api,
        repository: repository,
        catalogHash: '05' * 32,
        rendererHash: renderer,
        wait: () async {});
    await controller.refresh();
    api.lostVerify = false;
    await controller.reconcileUnknown();
    expect(controller.state.operationStatus, SyncOperationStatus.draft);
    expect(api.operations, isEmpty);
    expect(
        await repository.unresolved(api.caps['instanceId'] as String), isEmpty);
  });
  test('background after commit response defers readback and remains unknown',
      () async {
    await controller.prepareLoad(slot: 0, recipe: recipe(), activate: false);
    api.commitInSubmit = true;
    api.onSubmit = () => controller.setActive(false);
    final before = api.stateReads;
    await controller.confirm();
    expect(controller.state.operationStatus, SyncOperationStatus.unknown);
    expect(api.stateReads, before + 1);
  });
  test('identical complete recipe confirms fresh state without a write',
      () async {
    final parameters = <String, int>{};
    for (final e in (companionContract['parameters'] as Map).entries) {
      final p = e.value as Map;
      if ((p['filmIds'] == null || (p['filmIds'] as List).contains(33)) &&
          !(p['excludeFilmIds'] as List? ?? []).contains(33)) {
        parameters[e.key as String] = p['default'] as int;
      }
    }
    (api.current['slots'] as List)[0] = {
      'filmId': 33,
      'parameters': parameters,
      'customHash': null
    };
    final same = api.snapshot().recipeAt(0);
    await controller.prepareLoad(slot: 0, recipe: same, activate: false);
    await controller.confirm();
    expect(api.operations, isEmpty);
    expect(controller.state.operationStatus, SyncOperationStatus.synced);
  });
}
