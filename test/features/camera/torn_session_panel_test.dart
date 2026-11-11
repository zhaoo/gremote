import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/app_presence.dart';
import 'package:gremote/camera/companion/extensions_controller.dart';
import 'package:gremote/camera/companion/extensions_protocol.dart';
import 'package:gremote/features/camera/extensions_providers.dart';
import 'package:gremote/features/camera/extensions_page.dart';
import 'package:gremote/features/camera/torn_session_panel.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import 'extensions_page_test.dart' show AllExtensionsFake;
import '../../camera/extensions_controller_test.dart' show MemoryPending;

class PollingExtensionsFake extends AllExtensionsFake {
  int reads = 0, concurrent = 0, maxConcurrent = 0;
  Completer<void>? hold;
  @override
  Future<ExtensionSnapshot> extensionState() async {
    reads++;
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    try {
      await hold?.future;
      return await super.extensionState();
    } finally {
      concurrent--;
    }
  }
}

class UncertainTornFake extends PollingExtensionsFake {
  @override
  Future<ExtensionReceipt> submitExtension(
      Map<String, Object?> operation) async {
    submissions++;
    throw StateError('connection lost after submission');
  }
}

class AdvancingTornFake extends PollingExtensionsFake {
  AdvancingTornFake(this.stage, {this.readbackBusy = false});
  final int stage;
  final bool readbackBusy;
  @override
  Future<ExtensionReceipt> submitExtension(
      Map<String, Object?> operation) async {
    final receipt = await super.submitExtension(operation);
    settings['tornSession'] = stage;
    busy = readbackBusy;
    return receipt;
  }
}

class ReconciledTornFake extends PollingExtensionsFake {
  ExtensionReceipt? committed;
  bool acknowledge = false;
  @override
  Future<ExtensionReceipt> submitExtension(
      Map<String, Object?> operation) async {
    committed = await super.submitExtension(operation);
    throw StateError('committed response lost');
  }

  @override
  Future<ExtensionReceipt> extensionOperation(String id) async =>
      acknowledge ? committed! : await super.extensionOperation(id);
}

void main() {
  testWidgets(
      'retained router branch stops polling when TickerMode is disabled',
      (tester) async {
    final api = PollingExtensionsFake();
    final controller = CameraExtensionsController(
        api: api,
        store: MemoryPending(),
        instanceId: '01' * 16,
        bootstrap: () async {},
        blocked: () => false,
        onPending: (_) {});
    addTearDown(controller.dispose);
    await controller.refresh();
    var visible = true;
    late StateSetter rebuild;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          cameraExtensionsControllerProvider.overrideWithValue(controller),
          companionNetworkReadyProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
            home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return TickerMode(enabled: visible, child: const TornSessionPanel());
        })))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    final reads = api.reads;
    expect(reads, greaterThan(1));
    rebuild(() => visible = false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(api.reads, reads);
    expect(find.byType(TornSessionPanel), findsOneWidget);
    rebuild(() => visible = true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(api.reads, greaterThan(reads));
  });
  test(
      'reconnect retains unknown start until committed proof despite phase advancement',
      () async {
    final api = ReconciledTornFake();
    final controller = CameraExtensionsController(
        api: api,
        store: MemoryPending(),
        instanceId: '01' * 16,
        bootstrap: () async {},
        blocked: () => false,
        onPending: (_) {});
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.set('tornSession', 1);
    expect(controller.pending, isTrue);
    api.settings['tornSession'] = 2;
    await controller.refresh();
    expect(controller.pending, isTrue);
    expect(api.submissions, 1);
    api.acknowledge = true;
    await controller.refresh();
    expect(controller.pending, isFalse);
    expect(controller.snapshot!.values['tornSession'], 2);
    expect(api.submissions, 1);
  });
  for (final stage in [2, 3, 4]) {
    test('committed start clears pending when runtime advances to $stage',
        () async {
      final api = AdvancingTornFake(stage, readbackBusy: stage == 2);
      final store = MemoryPending();
      final controller = CameraExtensionsController(
          api: api,
          store: store,
          instanceId: '01' * 16,
          bootstrap: () async {},
          blocked: () => false,
          onPending: (_) {});
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.set('tornSession', 1);
      expect(controller.pending, isFalse);
      expect(store.saved, isNull);
      expect(controller.snapshot!.values['tornSession'], stage);
      expect(api.submissions, 1);
    });
  }

  testWidgets(
      'retained extensions stop polling when their tab becomes inactive',
      (tester) async {
    final api = PollingExtensionsFake();
    final controller = CameraExtensionsController(
        api: api,
        store: MemoryPending(),
        instanceId: '01' * 16,
        bootstrap: () async {},
        blocked: () => false,
        onPending: (_) {});
    addTearDown(controller.dispose);
    var active = true;
    late StateSetter rebuild;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          cameraExtensionsControllerProvider.overrideWithValue(controller),
          companionNetworkReadyProvider.overrideWithValue(true),
          companionIdentityHydrationProvider.overrideWith((_) async {}),
        ],
        child: MaterialApp(
            home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return IndexedStack(index: active ? 1 : 0, children: [
            const Text('胶卷'),
            CameraExtensions(active: active),
          ]);
        })))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('功能'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    final reads = api.reads;
    expect(reads, greaterThan(1));
    rebuild(() => active = false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(api.reads, reads);
    expect(find.byType(CameraExtensions, skipOffstage: false), findsOneWidget);
    rebuild(() => active = true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(api.reads, greaterThan(reads));
  });
  testWidgets(
      'shoot polling serializes GETs, stops in background, hidden tab and dispose',
      (tester) async {
    final api = PollingExtensionsFake()..settings['tornSession'] = 1;
    final controller = CameraExtensionsController(
        api: api,
        store: MemoryPending(),
        instanceId: '01' * 16,
        bootstrap: () async {},
        blocked: () => true,
        readBlocked: () => false,
        onPending: (_) {});
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          cameraExtensionsControllerProvider.overrideWithValue(controller),
          companionNetworkReadyProvider.overrideWithValue(true),
          shootPageVisibleProvider.overrideWith((_) => true),
        ],
        child: const MaterialApp(
            home: Scaffold(body: TornSessionPanel(shooting: true)))));
    await tester.pumpAndSettle();
    expect(find.text('撕纸叠映已开启'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(controller.canWrite, isFalse);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(TornSessionPanel)));
    api.hold = Completer<void>();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 6));
    expect(api.reads, 2);
    expect(api.maxConcurrent, 1);
    api.settings['tornSession'] = 2;
    api.hold!.complete();
    api.hold = null;
    await tester.pumpAndSettle();
    expect(find.text('撕纸叠映待拍素材'), findsOneWidget);
    api.settings['tornSession'] = 3;
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('撕纸叠映'), findsNothing);
    api.settings['tornSession'] = 4;
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('撕纸叠映未完成'), findsOneWidget);
    container.read(appForegroundProvider.notifier).state = false;
    await tester.pump();
    final before = api.reads;
    await tester.pump(const Duration(seconds: 6));
    expect(api.reads, before);
    container.read(appForegroundProvider.notifier).state = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(api.reads, before + 1);
    container.read(shootPageVisibleProvider.notifier).state = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(api.reads, before + 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
    expect(api.reads, before + 1);
    expect(api.submissions, 0);
  });

  testWidgets('busy and Half prevent commands', (tester) async {
    final api = PollingExtensionsFake()..settings['aspect'] = 6;
    final controller = CameraExtensionsController(
        api: api,
        store: MemoryPending(),
        instanceId: '01' * 16,
        bootstrap: () async {},
        blocked: () => false,
        onPending: (_) {});
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(ProviderScope(overrides: [
      cameraExtensionsControllerProvider.overrideWithValue(controller),
      companionNetworkReadyProvider.overrideWithValue(true),
    ], child: const MaterialApp(home: Scaffold(body: TornSessionPanel()))));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    await controller.set('tornSession', 1);
    expect(api.submissions, 0);
    api.settings['aspect'] = 0;
    api.busy = true;
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(api.submissions, 0);
  });

  testWidgets(
      'unknown start remains pending through disconnect and read-only reconnect',
      (tester) async {
    var connected = true;
    final api = UncertainTornFake();
    final controller = CameraExtensionsController(
        api: api,
        store: MemoryPending(),
        instanceId: '01' * 16,
        bootstrap: () async {},
        blocked: () => !connected,
        onPending: (_) {});
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(ProviderScope(overrides: [
      cameraExtensionsControllerProvider.overrideWithValue(controller),
      companionNetworkReadyProvider.overrideWith((_) => connected),
    ], child: const MaterialApp(home: Scaffold(body: TornSessionPanel()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(controller.pending, isTrue);
    expect(api.submissions, 1);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(TornSessionPanel)));
    connected = false;
    container.invalidate(companionNetworkReadyProvider);
    await tester.pumpAndSettle();
    final reads = api.reads;
    await tester.pump(const Duration(seconds: 6));
    expect(api.reads, reads);
    connected = true;
    container.invalidate(companionNetworkReadyProvider);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(api.reads, greaterThan(reads));
    expect(api.submissions, 1);
    expect(controller.pending, isTrue);
  });
}
