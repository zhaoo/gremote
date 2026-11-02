import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/darkroom/frame/frame_layout.dart';
import 'package:gremote/darkroom/lut/builtin_looks.dart';
import 'package:gremote/darkroom/model/edit_document.dart';
import 'package:gremote/darkroom/model/photo_edits.dart';
import 'package:gremote/darkroom/model/export_recipe.dart';
import 'package:gremote/features/darkroom/editor/editor_controller.dart';
import 'package:gremote/features/darkroom/editor/editor_page.dart';
import 'package:gremote/features/darkroom/editor/widgets/editor_panels.dart';
import 'package:gremote/features/darkroom/editor/widgets/frame_preview.dart';

import '../support/fake_media_gateway.dart';
import '../support/test_darkroom.dart';

Future<(TestDarkroom, ProviderContainer)> pumpEditor(WidgetTester tester,
    {bool locationAccess = true, Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final env = await TestDarkroom.create(
    gateway: FakeMediaGateway(
      entries: [mediaEntry(3)],
      exif: {3: grMeta()},
      locationAccess: locationAccess,
    ),
  );
  addTearDown(env.close);
  final container = ProviderContainer(overrides: env.overrides);
  addTearDown(container.dispose);
  await container.read(localMediaRepositoryProvider).scan().drain<void>();
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
        theme: GRemoteTheme.dark, home: const EditorPage(mediaId: 3)),
  ));
  await tester.pumpAndSettle();
  return (env, container);
}

double previewAspect(WidgetTester tester) => tester
    .widget<AspectRatio>(find.descendant(
        of: find.byKey(const ValueKey('frame-preview')),
        matching: find.byType(AspectRatio)))
    .aspectRatio;

Future<void> openTab(WidgetTester tester, String label) async {
  if (label == '信息' || label == '导出' || label == '画幅') {
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, label));
  } else {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tool grid opens adjustments and cancel restores the photo',
      (tester) async {
    final (_, container) = await pumpEditor(tester);
    expect(find.byKey(const ValueKey('editor-tool-grid')), findsOneWidget);
    await tester.tap(find.text('基础'));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider).first);
    slider.onChangeStart?.call(0);
    slider.onChanged?.call(1);
    slider.onChangeEnd?.call(1);
    await tester.pumpAndSettle();
    expect(
        container
            .read(editorProvider(3))
            .recipe
            .edits
            .value(PhotoAdjustment.exposure),
        1);
    await tester.tap(find.byTooltip('取消调整'));
    await tester.pumpAndSettle();
    expect(
        container
            .read(editorProvider(3))
            .recipe
            .edits
            .value(PhotoAdjustment.exposure),
        0);
  });
  testWidgets('cancelled press on compare restores the graded preview',
      (tester) async {
    final (_, container) = await pumpEditor(tester);
    await openTab(tester, 'LUT');
    await tester.tap(find.text(builtinLooks.first.name));
    await tester.pumpAndSettle();
    final state = container.read(editorProvider(3));
    expect(state.graded, isNot(same(state.base)));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byTooltip('按住对比')));
    await tester.pump();
    expect(
        tester
            .widget<FramePreview>(find.byKey(const ValueKey('frame-preview')))
            .image,
        same(state.base));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FramePreview>(find.byKey(const ValueKey('frame-preview')))
            .image,
        same(state.graded));
  });
  testWidgets('frame cards remain usable on a compact screen with large text',
      (tester) async {
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpEditor(tester, size: const Size(320, 568));
    await openTab(tester, '边框');
    expect(find.text('无边框'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('decodes a preview of the photo on open', (tester) async {
    final (env, _) = await pumpEditor(tester);
    await openTab(tester, 'LUT');
    expect(find.byKey(const ValueKey('frame-preview')), findsOneWidget);
    expect(env.engine.decoded, env.gateway.openedFds);
    expect(find.text('R003.JPG'), findsOneWidget);
  });

  testWidgets('new edits start with the full unframed original',
      (tester) async {
    final (_, c) = await pumpEditor(tester);
    expect(c.read(editorProvider(3)).layout!.overlays, isEmpty);
    expect(c.read(editorProvider(3)).recipe.frame, FrameStyle.none);
    expect(previewAspect(tester), 1.5);
  });

  testWidgets('choosing a LUT grades the preview', (tester) async {
    final (env, _) = await pumpEditor(tester);
    await openTab(tester, 'LUT');
    await tester.tap(find.text(builtinLooks.first.name));
    await tester.pumpAndSettle();
    expect(env.engine.lutCalls, contains(1.0));
    expect(find.textContaining('强度'), findsOneWidget);
  });

  testWidgets('frame ratio changes the preview aspect', (tester) async {
    await pumpEditor(tester);
    final before = previewAspect(tester);
    await openTab(tester, '画幅');
    await tester.tap(find.text('1:1'));
    await tester.pumpAndSettle();
    expect(previewAspect(tester), 1);
    expect(before, isNot(1));
  });

  testWidgets('choosing unframed preserves photo and saves the choice',
      (tester) async {
    final (env, container) = await pumpEditor(tester);
    await openTab(tester, '边框');
    await tester.tap(find.text('无边框'));
    await tester.pumpAndSettle();
    final layout = container.read(editorProvider(3)).layout!;
    expect(layout.overlays, isEmpty);
    expect(previewAspect(tester), 1.5);
    await tester.tap(find.byTooltip('完成调整'));
    await tester.pumpAndSettle();
    expect((await env.store.loadEdit(3))?.recipe.frame.name, 'none');
  });

  testWidgets('hidden fields disappear from the frame', (tester) async {
    final (_, container) = await pumpEditor(tester);
    await openTab(tester, '边框');
    await tester.tap(find.text('经典白边'));
    await tester.tap(find.byTooltip('完成调整'));
    await tester.pumpAndSettle();
    List<String> texts() => [
          for (final o in container.read(editorProvider(3)).layout!.overlays)
            for (final e in o.elements)
              if (e is FrameText) e.text,
        ];
    expect(texts(), contains('RICOH GR III'));
    await openTab(tester, '信息');
    await tester.tap(find.widgetWithText(FilterChip, FrameField.model.label));
    await tester.pumpAndSettle();
    expect(texts(), isNot(contains('RICOH GR III')));
  });

  testWidgets('keeping GPS needs media location access', (tester) async {
    await pumpEditor(tester, locationAccess: false);
    await openTab(tester, '导出');
    await tester.scrollUntilVisible(find.text('保留 GPS'), 60,
        scrollable: find.descendant(
            of: find.byType(ExportPanel), matching: find.byType(Scrollable)));
    final tile = tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '保留 GPS'));
    expect(tile.onChanged, isNull);
    expect(find.text('授予媒体位置权限'), findsOneWidget);
  });

  testWidgets('export publishes a copy and offers sharing', (tester) async {
    final (env, _) = await pumpEditor(tester);
    await tester.tap(find.widgetWithText(FilledButton, '导出'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(env.gateway.publishes, hasLength(1));
    expect(find.textContaining('已导出'), findsOneWidget);
    await tester.tap(find.text('分享'));
    expect(env.gateway.shared, hasLength(1));
  });

  testWidgets('saves the recipe as a preset', (tester) async {
    final (env, _) = await pumpEditor(tester);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('存为方案'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '夜街');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect((await env.store.presets()).single.name, '夜街');
  });

  testWidgets('edits are saved automatically', (tester) async {
    final (env, _) = await pumpEditor(tester);
    await openTab(tester, '信息');
    await tester.enterText(find.widgetWithText(TextField, '标题'), '清晨的海');
    await tester.pumpAndSettle();
    expect((await env.store.loadEdit(3))?.title, '清晨的海');
  });

  testWidgets(
      'photo drag follows selected adjustment and exports applied edits',
      (tester) async {
    final (env, c) = await pumpEditor(tester);
    await openTab(tester, '基础');
    await tester.tap(find.widgetWithText(ChoiceChip, '对比度'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const ValueKey('frame-preview')), const Offset(50, 0));
    await tester.pumpAndSettle();
    final e = c.read(editorProvider(3)).recipe.edits;
    expect(e.value(PhotoAdjustment.exposure), 0);
    expect(e.value(PhotoAdjustment.contrast), greaterThan(.1));
    await tester.tap(find.widgetWithText(FilledButton, '导出'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(env.engine.jobs.last.adjustments![2],
        closeTo(e.value(PhotoAdjustment.contrast), .00001));
    expect(find.byKey(const ValueKey('editor-tool-grid')), findsOneWidget);
  });

  testWidgets('landscape large text keeps apply and crop reachable',
      (tester) async {
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpEditor(tester, size: const Size(844, 390));
    await openTab(tester, '裁切');
    expect(find.byTooltip('完成调整'), findsOneWidget);
    await tester.ensureVisible(find.text('1:1'));
    await tester.tap(find.text('1:1'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('完成调整'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
