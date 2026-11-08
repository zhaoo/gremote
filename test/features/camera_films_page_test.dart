import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/camera/companion/generated_camera_contract.dart';
import 'package:gremote/camera/companion/companion_protocol.dart';
import 'package:gremote/camera/companion/companion_client.dart';
import 'package:gremote/camera/companion/sync_state.dart';
import '../camera/camera_sync_current_test.dart' show CurrentCamera;
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

class _GateCamera extends CurrentCamera {
  bool busy = false;
  @override
  CompanionSnapshot snapshot() =>
      CompanionSnapshot.fromJson({...super.snapshot().wire, 'busy': busy},
          contract: cameraContract);
}

class _MissingReceiptCamera extends FakeCompanion {
  @override
  Future<CompanionOperationReceipt> operation(String id) async =>
      throw const CompanionException('resultUnknown');
}

Future<void> _showFixture(WidgetTester tester, CompanionSyncController sync,
    {bool active = false, double scale = 1, bool accessible = false}) async {
  final catalog = CameraFilmCatalog.fromJson(
      jsonDecode(File('assets/films/camera-catalog.json').readAsStringSync()));
  await tester.pumpWidget(ProviderScope(
      overrides: [
        companionSyncControllerProvider.overrideWithValue(sync),
        companionIdentityStorageProvider.overrideWithValue(_IdentityStorage()),
        companionNetworkReadyProvider.overrideWithValue(active),
        cameraFilmCatalogProvider.overrideWith((ref) async => catalog),
        selectedFilmRecipeProvider.overrideWith((ref) => recipe()),
      ],
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  accessibleNavigation: accessible),
              child: child!),
          home: Scaffold(body: CameraFilmsPage(active: active)))));
  await tester.pump();
  await tester.pump();
}

void main() {
  sqfliteFfiInit();
  test('prepared slot never exposes a previous or completed preparation',
      () async {
    final api = CurrentCamera();
    final catalog = CameraFilmCatalog.fromJson(jsonDecode(
        File('assets/films/camera-catalog.json').readAsStringSync()));
    final sync = CompanionSyncController(
        api: api,
        repository: _MemoryRepository(),
        cameraCatalog: catalog,
        catalogHash: cameraCatalogHash,
        rendererHash: cameraRendererHash,
        wait: () async {});
    expect(sync.preparedSlot, isNull);
    await sync.prepareLoad(
        slot: 1, recipe: catalog.recipe(34), activate: false);
    expect(sync.preparedSlot, 0);
    final read = Completer<void>();
    api.waitRead = read;
    final replacement =
        sync.prepareLoad(slot: 0, recipe: catalog.recipe(35), activate: false);
    expect(sync.preparedSlot, isNull);
    read.complete();
    await replacement;
    expect(sync.preparedSlot, 1);
    await sync.confirm();
    expect(sync.state.hasPreparedLoad, isFalse);
    expect(sync.preparedSlot, isNull);
    sync.dispose();
  });

  testWidgets(
      'redirected confirmation freezes preparation across selection changes',
      (tester) async {
    final api = CurrentCamera();
    ((api.current['slots'] as List)[0]['parameters'] as Map)['grain'] = 1;
    final catalog = CameraFilmCatalog.fromJson(jsonDecode(
        File('assets/films/camera-catalog.json').readAsStringSync()));
    final sync = CompanionSyncController(
        api: api,
        repository: _MemoryRepository(),
        cameraCatalog: catalog,
        catalogHash: cameraCatalogHash,
        rendererHash: cameraRendererHash,
        wait: () async {});
    await sync.refresh();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          companionSyncControllerProvider.overrideWithValue(sync),
          companionIdentityStorageProvider
              .overrideWithValue(_IdentityStorage()),
          companionNetworkReadyProvider.overrideWithValue(true),
          cameraFilmCatalogProvider.overrideWith((ref) async => catalog),
        ],
        child: const MaterialApp(
            home: Scaffold(body: CameraFilmsPage(initialFilmId: 34)))));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('camera-film-slot-1')));
    await tester.pump();
    final previousToggle =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!;
    api.waitRead = Completer<void>();
    await tester.tap(find.text('写入槽位 02'));
    await tester.pump();
    // A queued control callback and another row tap cannot alter the prepared intent.
    previousToggle(false);
    await tester.tap(find.byKey(const ValueKey('camera-film-slot-2')));
    await tester.pump();
    api.waitRead!.complete();
    await tester.pumpAndSettle();
    expect(find.text('01 · Ektar 100'), findsOneWidget);
    expect(find.text('将覆盖：Ektar 100'), findsOneWidget);
    expect(find.text('写入后不切换当前胶卷'), findsNothing);
    expect(find.text('写入后使用'), findsWidgets);
    expect(api.operations, isEmpty);
    await tester.tap(find.text('确认写入'));
    await tester.pumpAndSettle();
    expect(api.operations, isNotEmpty);
    final writtenSlots = [
      for (final operation in api.operations)
        for (final patch in operation['patch'] as List) (patch as Map)['slot']
    ];
    expect(writtenSlots, [0]);
    expect(api.operations.last['activateSlot'], 0);
    expect(find.text('已核对完成'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });

  testWidgets('an open confirmation cannot submit a replacement preparation',
      (tester) async {
    final api = FakeCompanion();
    final sync = CompanionSyncController(
        api: api,
        repository: _MemoryRepository(),
        catalogHash: '05' * 32,
        rendererHash: '06' * 32,
        wait: () async {});
    await sync.refresh();
    await _showFixture(tester, sync);
    await tester.tap(find.text('写入槽位 01'));
    await tester.pumpAndSettle();
    final queuedConfirm = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '确认写入'))
        .onPressed!;
    await sync.prepareLoad(slot: 2, recipe: recipe(), activate: false);
    sync.setActive(true);
    queuedConfirm();
    await tester.pumpAndSettle();
    expect(api.operations, isEmpty);
    expect(find.text('03 · 800T'), findsOneWidget);
    expect(find.text('准备内容已变化，请返回后重新确认'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认写入'))
            .onPressed,
        isNull);
    expect(api.operations, isEmpty);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });

  testWidgets('stale busy and unsupported snapshots keep write disabled',
      (tester) async {
    final catalog = CameraFilmCatalog.fromJson(jsonDecode(
        File('assets/films/camera-catalog.json').readAsStringSync()));
    for (final condition in ['stale', 'busy', 'unsupported']) {
      final api = _GateCamera();
      api.stale = condition == 'stale';
      api.busy = condition == 'busy';
      if (condition == 'unsupported') {
        (api.caps['capabilities'] as Map)['readState'] = false;
      }
      final sync = CompanionSyncController(
          api: api,
          repository: _MemoryRepository(),
          cameraCatalog: catalog,
          catalogHash: cameraCatalogHash,
          rendererHash: cameraRendererHash);
      await sync.refresh();
      await _showFixture(tester, sync);
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, '写入槽位 01'))
              .onPressed,
          isNull,
          reason: condition);
      if (condition == 'busy') {
        expect(find.text('相机正忙，请稍后写入'), findsOneWidget);
      }
      expect(api.operations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      sync.dispose();
    }
  });

  testWidgets(
      'conflicts stay visible when folded and keep both saves local recipe',
      (tester) async {
    final api = FakeCompanion();
    final kept = <dynamic>[];
    final sync = CompanionSyncController(
        api: api,
        repository: _MemoryRepository(),
        catalogHash: '05' * 32,
        rendererHash: '06' * 32,
        keepLocalRecipe: (value) async {
          kept.add(value);
        });
    await sync.refresh();
    await _showFixture(tester, sync);
    await tester.tap(find.text('写入槽位 01'));
    await tester.pumpAndSettle();
    ((api.current['slots'] as List)[0]['parameters'] as Map)['grain'] = 1;
    await sync.refresh();
    await tester.pumpAndSettle();
    expect(find.text('手机 2'), findsOneWidget);
    expect(find.text('机身 1'), findsOneWidget);
    expect(find.text('保留两份'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认写入'))
            .onPressed,
        isNull);
    expect(api.operations, isEmpty);
    await tester.tap(find.text('保留两份'));
    await tester.tap(find.text('保存冲突选择'));
    await tester.pumpAndSettle();
    expect(kept, hasLength(1));
    expect(kept.single.parameters['grain'], 2);
    expect(find.text('手机配方单独保留，机内槽位不变'), findsOneWidget);
    expect(find.textContaining('将覆盖：'), findsNothing);
    expect(api.operations, isEmpty);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });

  testWidgets(
      'unknown result requires explicit retry of the identical operation',
      (tester) async {
    final api = _MissingReceiptCamera()..lost = true;
    final sync = CompanionSyncController(
        api: api,
        repository: _MemoryRepository(),
        catalogHash: '05' * 32,
        rendererHash: '06' * 32,
        wait: () async {});
    await _showFixture(tester, sync, active: true);
    await tester.tap(find.text('写入槽位 01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认写入'));
    await tester.pumpAndSettle();
    expect(sync.state.operationStatus, SyncOperationStatus.unknown);
    expect(api.operations, hasLength(1));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认写入'))
            .onPressed,
        isNull);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.text('核对结果'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '写入槽位 01'))
            .onPressed,
        isNull);
    expect(api.operations, hasLength(1));
    await tester.tap(find.text('核对结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试原操作'));
    await tester.pumpAndSettle();
    expect(api.operations, hasLength(1));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(api.operations, hasLength(1));
    // Polling refresh revokes retry readiness; obtain a fresh receipt check.
    await tester.tap(find.text('核对结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试原操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('以原操作重试'));
    await tester.pumpAndSettle();
    expect(api.operations, hasLength(2));
    expect(api.operations.last, api.operations.first);
    expect(sync.state.operationStatus, SyncOperationStatus.unknown);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });

  testWidgets(
      '320 large text and landscape keep confirmation usable with reduced motion',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeCompanion();
    final sync = CompanionSyncController(
        api: api,
        repository: _MemoryRepository(),
        catalogHash: '05' * 32,
        rendererHash: '06' * 32);
    await sync.refresh();
    await _showFixture(tester, sync, scale: 1.8, accessible: true);
    await tester.tap(find.byTooltip('更多胶卷操作'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<BottomSheet>(find.byType(BottomSheet))
            .animationController!
            .duration,
        Duration.zero);
    await tester.scrollUntilVisible(find.text('本地配方'), 150,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('本地配方').hitTestable(), findsOneWidget);
    Navigator.of(tester.element(find.text('本地配方'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('写入槽位 01'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<BottomSheet>(find.byType(BottomSheet))
            .animationController!
            .duration,
        Duration.zero);
    expect(find.text('确认写入').hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(find.text('参数明细'), 100,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('参数明细'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(640, 320));
    await tester.pumpAndSettle();
    expect(find.text('确认写入').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(api.operations, isEmpty);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });

  testWidgets('ten rows keep target controls visible and hide empty defaults',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = CurrentCamera();
    // A real schema2 empty slot contains read-only defaults too.
    final slots = api.current['slots'] as List;
    for (var i = 7; i < slots.length; i++) {
      slots[i] = {
        'filmId': 0,
        'parameters': {
          'grainSize': 0,
          'leakGain': 0,
          'leakPosition': 0,
          'leakSpread': 0,
          'leakVariation': 0
        },
        'customHash': null
      };
    }
    api.active = 1;
    final catalog = CameraFilmCatalog.fromJson(jsonDecode(
        File('assets/films/camera-catalog.json').readAsStringSync()));
    final sync = CompanionSyncController(
        api: api,
        repository: _MemoryRepository(),
        cameraCatalog: catalog,
        catalogHash: cameraCatalogHash,
        rendererHash: cameraRendererHash,
        wait: () async {});
    await sync.refresh();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          companionSyncControllerProvider.overrideWithValue(sync),
          companionIdentityStorageProvider
              .overrideWithValue(_IdentityStorage()),
          companionNetworkReadyProvider.overrideWithValue(false),
          cameraFilmCatalogProvider.overrideWith((ref) async => catalog),
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: CameraFilmsPage(active: false, initialFilmId: 321)))));
    await tester.pump();
    await tester.pump();
    // The primary action is reachable without scrolling through ten cards.
    expect(find.text('写入槽位 01').hitTestable(), findsOneWidget);
    expect(find.textContaining('尺寸 0 · 漏光 0'), findsNothing);
    expect(find.text('导入胶卷数据'), findsNothing);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('camera-film-slot-9')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('camera-film-slot-9')));
    await tester.pump();
    expect(find.text('写入槽位 10').hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('写入槽位 10'));
    await tester.pumpAndSettle();
    // Schema2 uses the first empty slot; confirm the actual controller target.
    expect(sync.preparedSlot, 7);
    expect(find.text('08 · 空槽'), findsOneWidget);
    expect(find.textContaining('将覆盖：'), findsNothing);
    expect(api.operations, isEmpty);
    sync.setActive(true); // Only this in-memory fake can submit in this test.
    await tester.tap(find.text('确认写入'));
    await tester.pumpAndSettle();
    expect([
      for (final operation in api.operations)
        for (final patch in operation['patch'] as List) (patch as Map)['slot']
    ], [
      7
    ]);
    expect(api.operations.last['activateSlot'], 7);
    expect(sync.preparedSlot, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });

  testWidgets('confirmation names occupied target and folds parameter details',
      (tester) async {
    final api = FakeCompanion();
    final sync = CompanionSyncController(
        api: api,
        repository: _MemoryRepository(),
        catalogHash: '05' * 32,
        rendererHash: '06' * 32,
        wait: () async {});
    await sync.refresh();
    final catalog = FilmCatalog.fromJson(
        jsonDecode(File('assets/films/catalog.json').readAsStringSync()));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          companionSyncControllerProvider.overrideWithValue(sync),
          companionIdentityStorageProvider
              .overrideWithValue(_IdentityStorage()),
          companionNetworkReadyProvider.overrideWithValue(false),
          filmCatalogProvider.overrideWith((ref) async => catalog),
          selectedFilmRecipeProvider.overrideWith((ref) => recipe()),
        ],
        child: const MaterialApp(
            home: Scaffold(body: CameraFilmsPage(active: false)))));
    await tester.pump();
    await tester.tap(find.text('写入槽位 01'));
    await tester.pumpAndSettle();
    expect(find.text('将覆盖：800T'), findsOneWidget);
    expect(find.text('写入后使用'), findsWidgets);
    expect(find.textContaining('颗粒 2 · 尺寸 1'), findsNothing);
    expect(find.textContaining('已排队'), findsNothing);
    expect(api.operations, isEmpty);
    await tester.tap(find.text('参数明细'));
    await tester.pumpAndSettle();
    expect(find.textContaining('颗粒 2 · 尺寸 1'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(api.operations, isEmpty);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });

  testWidgets(
      'current ten slots and camera-only newest selection stay read only before confirmation',
      (tester) async {
    final api = CurrentCamera();
    final catalog = CameraFilmCatalog.fromJson(jsonDecode(
        File('assets/films/camera-catalog.json').readAsStringSync()));
    final controller = CompanionSyncController(
        api: api,
        repository: _MemoryRepository(),
        catalogHash: cameraCatalogHash,
        rendererHash: cameraRendererHash,
        cameraCatalog: catalog);
    await controller.refresh();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          companionSyncControllerProvider.overrideWithValue(controller),
          companionIdentityStorageProvider
              .overrideWithValue(_IdentityStorage()),
          companionNetworkReadyProvider.overrideWithValue(false),
          cameraFilmCatalogProvider.overrideWith((ref) async => catalog)
        ],
        child: const MaterialApp(
            home: Scaffold(body: CameraFilmsPage(active: false)))));
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('camera-film-slot-9')), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('机内使用中'), findsOneWidget);
    await tester.tap(find.byTooltip('更多胶卷操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('相机目录'));
    await tester.pumpAndSettle();
    expect(find.text('搜索胶卷'), findsOneWidget);
    await tester.enterText(find.byType(TextField), catalog.film(321).name);
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, catalog.film(321).name));
    await tester.pumpAndSettle();
    expect(find.text('调整参数'), findsOneWidget);
    expect(api.operations, isEmpty);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('film data remains available without exposing manual pairing',
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
    expect(find.text('导入配对文件'), findsNothing);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('camera-film-slot-3')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('camera-film-slot-3')));
    await tester.pump();
    expect(api.operations, isEmpty);
    await tester.tap(find.byTooltip('更多胶卷操作'));
    await tester.pumpAndSettle();
    expect(find.text('导入配对文件'), findsNothing);
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
    await tester.tap(find.text('写入槽位 01'));
    await tester.pump();
    await tester.pump();
    expect(api.operations, isEmpty);
    expect(find.text('确认装卷'), findsOneWidget);
    final readsAtConfirmation = api.stateReads;
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(api.stateReads, readsAtConfirmation);
    expect(api.operations, isEmpty);
    await tester.tap(find.text('确认写入'));
    await tester.pump();
    await tester.pump();
    expect(api.operations, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    final readsAfterWrite = api.stateReads;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(api.stateReads, greaterThan(readsAfterWrite));
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
    visible.dispose();
  });
}
