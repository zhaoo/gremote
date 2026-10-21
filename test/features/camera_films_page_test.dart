import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gremote/camera/companion/companion_sync_controller.dart';
import 'package:gremote/camera/companion/pairing_store.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/film/store/sync_repository.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:gremote/features/film_workbench/camera_films_page.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import 'package:gremote/features/film_workbench/workbench_providers.dart';
import '../camera/companion_sync_controller_test.dart'
    show FakeCompanion, recipe;

class _IdentityStorage extends PairingIdentityStorage {
  @override
  Future<PairingIdentity?> read() async => null;
}

class _UnusedDb extends Fake implements Database {}

class _MemoryRepository extends SyncRepository {
  _MemoryRepository() : super(_UnusedDb());
  Map<String, dynamic>? saved;
  final operations = <String, Map<String, Object?>>{};
  @override
  Future<Map<String, dynamic>?> baseline(String id) async => saved;
  @override
  Future<void> saveBaseline(String id, Map<String, Object?> value) async {
    saved = Map<String, dynamic>.from(value);
  }

  @override
  Future<List<Map<String, Object?>>> unresolved(String id) async => [];
  @override
  Future<void> saveOperation(
      {required String requestId,
      required String instanceId,
      required Map<String, Object?> payload,
      required String status}) async {
    operations[requestId] = {'payload': payload, 'status': status};
  }
}

void main() {
  sqfliteFfiInit();
  testWidgets(
      'real five slots browse without writes; offline empty state has import action',
      (tester) async {
    final db = (await tester.runAsync(() => GRemoteDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath)))!;
    final api = FakeCompanion();
    final controller = CompanionSyncController(
        api: api,
        repository: SyncRepository(db),
        catalogHash: '05' * 32,
        rendererHash: '06' * 32,
        wait: () async {});
    await tester.runAsync(controller.refresh);
    final catalog = FilmCatalog.fromJson(
        jsonDecode(File('assets/films/catalog.json').readAsStringSync())
            as Map<String, dynamic>);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          companionSyncControllerProvider.overrideWithValue(controller),
          companionIdentityStorageProvider
              .overrideWithValue(_IdentityStorage()),
          companionNetworkReadyProvider.overrideWithValue(false),
          filmCatalogProvider.overrideWith((ref) async => catalog),
          selectedFilmRecipeProvider.overrideWith((ref) => recipe())
        ],
        child: const MaterialApp(
            home: Scaffold(body: CameraFilmsPage(active: false)))));
    await tester.pump();
    expect(find.text('机内使用中'), findsOneWidget);
    expect(find.byKey(const ValueKey('camera-film-slot-0')), findsOneWidget);
    expect(find.text('导入配对文件'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('camera-film-slot-3')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('camera-film-slot-3')));
    await tester.pump();
    expect(api.operations, isEmpty);
    await tester.scrollUntilVisible(find.text('导入胶卷数据'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('导入胶卷数据'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.runAsync(db.close);
  });
  testWidgets(
      'hidden or background page stops polling; confirmation owns the write',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeCompanion();
    final sync = CompanionSyncController(
        api: api,
        repository: _MemoryRepository(),
        catalogHash: '05' * 32,
        rendererHash: '06' * 32,
        wait: () async {});
    final visible = ValueNotifier(true);
    final catalog = FilmCatalog.fromJson(
        jsonDecode(File('assets/films/catalog.json').readAsStringSync())
            as Map<String, dynamic>);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          companionSyncControllerProvider.overrideWithValue(sync),
          companionIdentityStorageProvider
              .overrideWithValue(_IdentityStorage()),
          companionNetworkReadyProvider.overrideWithValue(true),
          filmCatalogProvider.overrideWith((ref) async => catalog),
          selectedFilmRecipeProvider.overrideWith((ref) => recipe())
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.4),
                    disableAnimations: true),
                child: child!),
            home: Scaffold(
                body: ValueListenableBuilder(
                    valueListenable: visible,
                    builder: (context, value, child) =>
                        CameraFilmsPage(active: value))))));
    await tester.pump();
    await tester.pump();
    expect(api.stateReads, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(api.stateReads, 2);
    visible.value = false;
    await tester.pump();
    final before = api.stateReads;
    await tester.pump(const Duration(seconds: 6));
    expect(api.stateReads, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 6));
    expect(api.stateReads, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    visible.value = true;
    await tester.pump();
    await tester.pump();
    expect(api.stateReads, before + 1);
    await tester.scrollUntilVisible(find.text('装入槽位 01'), 220,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('装入槽位 01'));
    await tester.pump();
    await tester.tap(find.text('装入槽位 01'));
    await tester.pump();
    await tester.pump();
    expect(api.operations, isEmpty);
    expect(find.text('确认装卷'), findsOneWidget);
    await tester.tap(find.text('确认装入'));
    await tester.pump();
    await tester.pump();
    expect(api.operations, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
    visible.dispose();
  });
}
