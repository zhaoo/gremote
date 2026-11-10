import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/camera/companion/extensions_controller.dart';
import 'package:gremote/camera/companion/extensions_protocol.dart';
import 'package:gremote/camera/companion/companion_client.dart';
import 'package:gremote/features/camera/extensions_page.dart';
import 'package:gremote/features/camera/extensions_providers.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import '../../camera/extensions_controller_test.dart';

class AllExtensionsFake extends ExtensionFake {
  final settings = <String, int>{
    'tornSession': 0,
    'vignetteEnabled': 0,
    'vignetteStrength': 3,
    'imprint': 0,
    'quickSwitch': 0,
    'quickSwitchA': 0,
    'quickSwitchB': 1,
    'hdf': 0,
    'border': 0,
    'grainMode': 0,
    'grainSize': 1,
    'leakGain': 0,
    'leakPosition': 0,
    'leakSpread': 1,
    'blurGain': 0,
    'blurRange': 1,
    'stamp': 0,
    'stampFormat': 0,
    'stampCorner': 3,
    'stampColor': 0,
    'filmNameStamp': 0,
    'focalA': 28,
    'focalB': 35,
    'focalSlot': 0,
    'aspect': 0,
  };
  bool busy = false;
  String revision = '04';
  final operations = <Map<String, Object?>>[];
  Completer<void>? commitReady, readbackReady;
  final excludedCapabilities = <String>{};
  final excludedSnapshot = <String>{};
  @override
  Future<ExtensionCapabilities> extensionCapabilities() async {
    final caps = extCaps();
    for (final field in caps['fields'] as List) {
      field['supported'] = !excludedCapabilities.contains(field['key']);
    }
    return ExtensionCapabilities.fromJson(caps);
  }

  @override
  Future<ExtensionSnapshot> extensionState() async {
    if (submissions > 0) await readbackReady?.future;
    return ExtensionSnapshot.fromJson({
      ...extSnapshot(revision: revision),
      'busy': busy,
      'supported': settings.keys
          .where((key) => !excludedSnapshot.contains(key))
          .toList(),
      'values': {
        for (final entry in settings.entries)
          if (!excludedSnapshot.contains(entry.key)) entry.key: entry.value
      },
    });
  }

  @override
  Future<ExtensionReceipt> submitExtension(
      Map<String, Object?> operation) async {
    submissions++;
    operations.add(Map.of(operation));
    await commitReady?.future;
    settings[operation['field'] as String] = operation['value'] as int;
    return ExtensionReceipt.fromJson({
      'requestId': operation['requestId'],
      'bootId': bootId,
      'status': 'committed',
      'snapshot': {
        ...extSnapshot(revision: revision),
        'busy': busy,
        'supported': settings.keys.toList(),
        'values': settings
      },
    });
  }
}

Future<void> pumpExtensions(
    WidgetTester tester, CameraExtensionsController? controller,
    {bool connected = true, bool reducedMotion = false}) async {
  await tester.pumpWidget(ProviderScope(
      overrides: [
        cameraExtensionsControllerProvider.overrideWithValue(controller),
        companionNetworkReadyProvider.overrideWithValue(connected),
        companionIdentityHydrationProvider.overrideWith((_) async {}),
      ],
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reducedMotion),
              child: child!),
          theme: GRemoteTheme.dark,
          home: const Scaffold(body: CameraExtensions()))));
  await tester.pumpAndSettle();
}

CameraExtensionsController makeController(ExtensionFake api,
        {bool Function()? blocked}) =>
    CameraExtensionsController(
        api: api,
        store: MemoryPending(),
        instanceId: '01' * 16,
        bootstrap: () async {},
        blocked: blocked ?? () => false,
        onPending: (_) {});

void main() {
  testWidgets('torn session offers commands, never writable native stages',
      (tester) async {
    final api = AllExtensionsFake();
    final controller = makeController(api);
    addTearDown(controller.dispose);
    await pumpExtensions(tester, controller);
    await tester.tap(find.text('功能'));
    await tester.pumpAndSettle();
    expect(find.text('撕纸叠映'), findsOneWidget);
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();
    expect(api.operations.single['field'], 'tornSession');
    expect(api.operations.single['value'], 1);
    expect(find.text('拍摄轮廓'), findsOneWidget);
    await tester.tap(find.text('重新开始'));
    await tester.pumpAndSettle();
    expect(api.operations, hasLength(2));
    api.settings['tornSession'] = 2;
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('拍摄素材'), findsOneWidget);
    await controller.set('tornSession', 3);
    expect(api.operations, hasLength(2));
    await tester.tap(find.text('取消叠映'));
    await tester.pumpAndSettle();
    expect(api.operations.last['value'], 0);
  });
  testWidgets('imprint choice writes its raw value and shows native readback',
      (tester) async {
    final api = AllExtensionsFake();
    final controller = makeController(api);
    addTearDown(controller.dispose);
    await pumpExtensions(tester, controller);
    await tester.tap(find.text('效果'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('extension-field-imprint')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('宝可梦'), 100,
        scrollable: find
            .descendant(
                of: find.byType(BottomSheet), matching: find.byType(Scrollable))
            .last);
    await tester.tap(find.text('宝可梦').last);
    await tester.pumpAndSettle();
    expect(controller.snapshot!.values['imprint'], 7);
    expect(controller.message, '已保存');
    expect(api.operations, hasLength(1));
    expect(api.operations.single['field'], 'imprint');
    expect(api.operations.single['value'], 7);
  });

  testWidgets('vignette switch preserves independently selected strength',
      (tester) async {
    final api = AllExtensionsFake();
    final controller = makeController(api);
    addTearDown(controller.dispose);
    await pumpExtensions(tester, controller);
    await tester.tap(find.text('效果'));
    await tester.pumpAndSettle();
    final control =
        find.byKey(const ValueKey('extension-field-vignetteEnabled'));
    await tester.scrollUntilVisible(control, 150,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(
        find.descendant(of: control, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    await tester
        .tap(find.descendant(of: control, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(api.operations.single['field'], 'vignetteEnabled');
    expect(api.operations.single['value'], 1);
    expect(controller.snapshot!.values['vignetteStrength'], 3);
  });

  testWidgets(
      'groups start collapsed and retain all fields with one group open',
      (tester) async {
    final controller = makeController(AllExtensionsFake());
    addTearDown(controller.dispose);
    await pumpExtensions(tester, controller);
    expect(find.text('HDF'), findsNothing);
    expect(find.text('快切 A'), findsNothing);
    const groups = <String, List<String>>{
      '功能': ['快切', '快切 A', '快切 B', 'Half'],
      '效果': ['HDF', '边框', '颗粒', '颗粒尺寸', '漏光', '漏光位置', '漏光范围', '模糊', '模糊范围'],
      '水印': ['时间', '日期格式', '位置', '颜色', '胶卷名称'],
      '焦距': ['第一档', '第二档', '当前焦距'],
      '画幅': ['画幅'],
    };
    const groupKeys = <String, List<String>>{
      '功能': ['quickSwitch', 'quickSwitchA', 'quickSwitchB'],
      '效果': [
        'hdf',
        'border',
        'grainMode',
        'grainSize',
        'leakGain',
        'leakPosition',
        'leakSpread',
        'blurGain',
        'blurRange'
      ],
      '水印': [
        'stamp',
        'stampFormat',
        'stampCorner',
        'stampColor',
        'filmNameStamp'
      ],
      '焦距': ['focalA', 'focalB', 'focalSlot'],
      '画幅': ['aspect'],
    };
    for (final group in groups.entries) {
      await tester.scrollUntilVisible(
          find.byKey(ValueKey('extension-group-${group.key}')), 160,
          scrollable: find.byType(Scrollable).first);
      await tester
          .ensureVisible(find.byKey(ValueKey('extension-group-${group.key}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('extension-group-${group.key}')));
      await tester.pumpAndSettle();
      for (final key in groupKeys[group.key]!) {
        expect(find.byKey(ValueKey('extension-field-$key')), findsOneWidget);
      }
      for (final label in group.value) {
        expect(
            find.ancestor(
                of: find.text(label), matching: find.byType(ListTile)),
            findsWidgets);
      }
      if (group.key != '功能') expect(find.text('快切 A'), findsNothing);
      if (group.key != '效果') expect(find.text('HDF'), findsNothing);
    }
    expect(find.text('开关机画面暂不支持远程设置'), findsOneWidget);
    expect(find.textContaining('固件'), findsNothing);
  });

  testWidgets(
      'Half submits its aspect wire value directly and displays readback',
      (tester) async {
    final api = AllExtensionsFake();
    final controller = makeController(api);
    addTearDown(controller.dispose);
    await pumpExtensions(tester, controller);
    expect(find.text('28 mm / 35 mm'), findsOneWidget);
    await tester.tap(find.text('功能'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(api.submissions, 1);
    expect(api.operations.single['field'], 'aspect');
    expect(api.operations.single['value'], 6);
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.snapshot!.values['aspect'], 6);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(api.submissions, 2);
    expect(api.operations.last['value'], 0);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('selection waits for committed receipt and fresh readback',
      (tester) async {
    final api = AllExtensionsFake()
      ..commitReady = Completer<void>()
      ..readbackReady = Completer<void>();
    final controller = makeController(api);
    addTearDown(controller.dispose);
    await pumpExtensions(tester, controller, reducedMotion: true);
    await tester.tap(find.text('效果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('弱'));
    await tester.pumpAndSettle();
    expect(api.submissions, 1);
    expect(api.operations.single['field'], 'hdf');
    expect(api.operations.single['value'], 1);
    expect(api.operations.single['baseRevision'], '04' * 32);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('已保存'), findsNothing);
    expect(controller.snapshot!.values['hdf'], 0);
    expect(controller.canWrite, isFalse);
    api.commitReady!.complete();
    await tester.pumpAndSettle();
    expect(find.text('已保存'), findsNothing);
    expect(controller.snapshot!.values['hdf'], 0);
    api.readbackReady!.complete();
    await tester.pumpAndSettle();
    expect(controller.snapshot!.values['hdf'], 1);
    expect(controller.message, '已保存');
    expect(find.text('已保存'), findsWidgets);
    expect(api.submissions, 1);
  });

  testWidgets('a refreshed revision invalidates an open chooser',
      (tester) async {
    final api = AllExtensionsFake();
    final controller = makeController(api);
    addTearDown(controller.dispose);
    await pumpExtensions(tester, controller);
    await tester.tap(find.text('效果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HDF'));
    await tester.pumpAndSettle();
    final originalChoice = tester
        .widget<RadioListTile<int>>(
            find.widgetWithText(RadioListTile<int>, '弱'))
        .onChanged!;
    api.revision = '05';
    api.settings['hdf'] = 3;
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RadioListTile<int>>(
                find.widgetWithText(RadioListTile<int>, '弱'))
            .onChanged,
        isNull);
    // Even a choice already queued before the refresh must keep its old revision.
    originalChoice(1);
    await tester.pumpAndSettle();
    expect(api.submissions, 0);
    expect(controller.snapshot!.values['hdf'], 3);
    await tester.tap(find.text('HDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('弱'));
    await tester.pumpAndSettle();
    expect(api.submissions, 1);
    expect(api.operations.single['baseRevision'], '05' * 32);
  });

  testWidgets('choosing the current value does not write', (tester) async {
    final api = AllExtensionsFake();
    final controller = makeController(api);
    addTearDown(controller.dispose);
    await pumpExtensions(tester, controller);
    await tester.tap(find.text('效果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RadioListTile<int>, '关闭'));
    await tester.pumpAndSettle();
    expect(api.submissions, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('live quick-switch pairing gate disables an already open chooser',
      (tester) async {
    final api = AllExtensionsFake();
    final controller = makeController(api);
    addTearDown(controller.dispose);
    await pumpExtensions(tester, controller);
    await tester.tap(find.text('功能'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('快切 A'));
    await tester.pumpAndSettle();
    api.settings['quickSwitch'] = 1;
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RadioListTile<int>>(
                find.widgetWithText(RadioListTile<int>, '鲜艳'))
            .onChanged,
        isNull);
    expect(api.submissions, 0);
  });

  for (final gate in ['busy', 'capability', 'snapshot']) {
    testWidgets('$gate prevents a write from an already open chooser',
        (tester) async {
      final api = AllExtensionsFake();
      final controller = makeController(api);
      addTearDown(controller.dispose);
      await pumpExtensions(tester, controller);
      await tester.tap(find.text('效果'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HDF'));
      await tester.pumpAndSettle();
      final originalChoice = tester
          .widget<RadioListTile<int>>(
              find.widgetWithText(RadioListTile<int>, '弱'))
          .onChanged!;
      if (gate == 'busy') api.busy = true;
      if (gate == 'capability') api.excludedCapabilities.add('hdf');
      if (gate == 'snapshot') api.excludedSnapshot.add('hdf');
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<RadioListTile<int>>(
                  find.widgetWithText(RadioListTile<int>, '弱'))
              .onChanged,
          isNull);
      originalChoice(1);
      await tester.pumpAndSettle();
      expect(api.submissions, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('$gate disables field and Half writes', (tester) async {
      final api = AllExtensionsFake();
      if (gate == 'busy') api.busy = true;
      if (gate == 'capability') {
        api.excludedCapabilities.addAll(['quickSwitch', 'aspect']);
      }
      if (gate == 'snapshot') {
        api.excludedSnapshot.addAll(['quickSwitch', 'aspect']);
      }
      final controller = makeController(api);
      addTearDown(controller.dispose);
      await pumpExtensions(tester, controller);
      if (gate == 'snapshot') {
        expect(
            find.descendant(
                of: find.byKey(const ValueKey('extension-group-画幅')),
                matching: find.text('此项暂不支持')),
            findsOneWidget);
      }
      await tester.tap(find.text('功能'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ListTile>(
                  find.byKey(const ValueKey('extension-field-quickSwitch')))
              .onTap,
          isNull);
      if (gate != 'snapshot') {
        expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      }
      if (gate == 'busy') expect(find.text('机身忙碌 · 暂不可设置'), findsOneWidget);
      expect(api.submissions, 0);
    });
  }

  for (final size in [const Size(320, 568), const Size(844, 320)]) {
    testWidgets('large text groups and direct choice remain usable at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
      final api = AllExtensionsFake();
      final controller = makeController(api);
      addTearDown(controller.dispose);
      await pumpExtensions(tester, controller);
      await tester.scrollUntilVisible(find.text('效果'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('效果'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('HDF'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('HDF'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('弱'), 80,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('弱'));
      await tester.pumpAndSettle();
      expect(api.submissions, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'reduced motion keeps a loading page still and gates writes until the GET completes',
      (tester) async {
    final ready = Completer<void>();
    final controller = CameraExtensionsController(
        api: AllExtensionsFake(),
        store: MemoryPending(),
        instanceId: '01' * 16,
        bootstrap: () => ready.future,
        blocked: () => false,
        onPending: (_) {});
    addTearDown(controller.dispose);
    await pumpExtensions(tester, controller, reducedMotion: true);
    expect(find.text('正在读取机身设置…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '重新读取'))
            .onPressed,
        isNull);
    await tester.tap(find.text('效果'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('extension-field-hdf')))
            .onTap,
        isNull);
    ready.complete();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('extension-field-hdf')))
            .onTap,
        isNotNull);
    await tester.tap(find.text('HDF'));
    await tester.pump();
    expect(ModalRoute.of(tester.element(find.text('弱')))!.animation!.status,
        AnimationStatus.completed);
    await tester.tap(find.text('弱'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.snapshot!.values['hdf'], 1);
  });

  testWidgets(
      'a failed refresh keeps the last value visible but disables editing',
      (tester) async {
    final api = ReadFailureExtensionFake(null);
    final controller = makeController(api);
    addTearDown(controller.dispose);
    await pumpExtensions(tester, controller);
    await tester.tap(find.text('效果'));
    await tester.pumpAndSettle();
    api.failure = StateError('lost GET');
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('读取失败，请重新读取'), findsOneWidget);
    final row = find.byKey(const ValueKey('extension-field-hdf'));
    expect(find.descendant(of: row, matching: find.text('关闭')), findsOneWidget);
    expect(tester.widget<ListTile>(row).onTap, isNull);
    expect(controller.pending, isFalse);
  });

  testWidgets('refresh updates current value in the expanded group',
      (tester) async {
    final api = ExtensionFake();
    final controller = makeController(api);
    addTearDown(controller.dispose);
    await pumpExtensions(tester, controller);
    await tester.tap(find.text('效果'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('extension-field-hdf')),
            matching: find.text('关闭')),
        findsOneWidget);
    api.value = 3;
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('extension-field-hdf')),
            matching: find.text('强')),
        findsOneWidget);
  });

  for (final (error, expected) in <(Object, String)>[
    (StateError('offline'), '读取失败，请重新读取'),
    (const CompanionException('bridgeUnavailable'), '机内服务未就绪，请稍后重新读取'),
    (const CompanionException('extensionsUnsupported'), '此相机不支持扩展设置'),
    (const CompanionException('unsupportedProtocol'), '扩展设置协议不兼容，暂不可设置'),
  ]) {
    testWidgets(
        'read status distinguishes $expected without claiming an unfinished write',
        (tester) async {
      final api = ReadFailureExtensionFake(error);
      final controller = makeController(api);
      addTearDown(controller.dispose);
      await pumpExtensions(tester, controller);
      expect(find.text(expected), findsOneWidget);
      expect(find.textContaining('操作未完成'), findsNothing);
      expect(find.text('核对当前设置'), findsNothing);
      await tester.tap(find.text('效果'));
      await tester.pumpAndSettle();
      final field = tester
          .widget<ListTile>(find.byKey(const ValueKey('extension-field-hdf')));
      expect(field.onTap, isNull);
      expect(api.submissions, 0);
    });
  }

  testWidgets(
      'pending write keeps reconciliation visible and all edits disabled',
      (tester) async {
    final api = ExtensionFake()..uncertain = true;
    final controller = makeController(api);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.set('hdf', 2);
    await pumpExtensions(tester, controller);
    expect(find.text('结果待核对，请勿重复提交'), findsOneWidget);
    expect(find.text('核对当前设置'), findsOneWidget);
    await tester.tap(find.text('效果'));
    await tester.pumpAndSettle();
    final field = tester
        .widget<ListTile>(find.byKey(const ValueKey('extension-field-hdf')));
    expect(field.onTap, isNull);
    expect(api.submissions, 1);
    await tester.tap(find.text('核对当前设置'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('重新读取机身。未决操作需重启相机后再核对，不会重复提交。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.pending, isTrue);
    expect(api.submissions, 1);
  });

  testWidgets(
      'external write gate disables edits and a previously open chooser',
      (tester) async {
    var blocked = false;
    final api = ExtensionFake();
    final controller = makeController(api, blocked: () => blocked);
    addTearDown(controller.dispose);
    await pumpExtensions(tester, controller);
    await tester.tap(find.text('效果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HDF'));
    await tester.pumpAndSettle();
    blocked = true;
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RadioListTile<int>>(
                find.widgetWithText(RadioListTile<int>, '弱'))
            .onChanged,
        isNull);
    Navigator.of(tester.element(find.text('弱'))).pop();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('extension-field-hdf')))
            .onTap,
        isNull);
    expect(api.submissions, 0);
  });

  testWidgets(
      'unpaired camera shows disabled settings without an unlock button',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          cameraExtensionsControllerProvider.overrideWithValue(null),
          companionNetworkReadyProvider.overrideWithValue(false),
          companionIdentityHydrationProvider.overrideWith((_) async {}),
        ],
        child: MaterialApp(
            theme: GRemoteTheme.dark,
            home: const Scaffold(body: CameraExtensions()))));
    await tester.pumpAndSettle();
    expect(find.text('HDF'), findsNothing);
    await tester.tap(find.text('效果'));
    await tester.pumpAndSettle();
    expect(find.text('HDF'), findsOneWidget);
    final row = tester.widget<ListTile>(find
        .ancestor(of: find.text('HDF'), matching: find.byType(ListTile))
        .first);
    expect(row.onTap, isNull);
    expect(row.enabled, isFalse);
    expect(find.widgetWithText(FilledButton, '连接相机'), findsNothing);
    await tester.tap(find.text('HDF'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  for (final width in [320.0, 390.0]) {
    testWidgets(
        'extension HDF choice submits once with real readback at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
      final api = ExtensionFake(), store = MemoryPending();
      final controller = CameraExtensionsController(
          api: api,
          store: store,
          instanceId: '01' * 16,
          bootstrap: () async {},
          blocked: () => false,
          onPending: (_) {});
      addTearDown(controller.dispose);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            cameraExtensionsControllerProvider.overrideWithValue(controller),
            companionNetworkReadyProvider.overrideWithValue(true),
            companionIdentityHydrationProvider.overrideWith((_) async {})
          ],
          child: MaterialApp(
              theme: GRemoteTheme.dark,
              home: const Scaffold(body: CameraExtensions()))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('效果'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('HDF'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('HDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('弱'));
      await tester.pumpAndSettle();
      expect(api.submissions, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.snapshot!.values['hdf'], 1);
      expect(find.text('已保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
