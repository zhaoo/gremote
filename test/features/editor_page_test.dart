import 'dart:async';
import 'package:gremote/darkroom/store/darkroom_store.dart';
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

class GatedEditStore extends DarkroomStore {
  GatedEditStore(super.db, this.gate);
  final Future<void> gate;
  @override
  Future<void> saveEdit(EditDocument doc) async {
    await gate;
    await super.saveEdit(doc);
  }
}

Future<(TestDarkroom, ProviderContainer)> pumpEditor(WidgetTester tester,
    {bool locationAccess = true,
    Size size = const Size(390, 844),
    Future<void>? saveGate,
    ExportRecipe? initialRecipe}) async {
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
  if (initialRecipe != null) {
    await env.store.saveEdit(EditDocument(
        mediaId: 3, recipe: initialRecipe, updatedAt: DateTime(2026)));
  }
  final container = ProviderContainer(overrides: [
    ...env.overrides,
    if (saveGate != null)
      darkroomStoreProvider.overrideWithValue(GatedEditStore(env.db, saveGate))
  ]);
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
  testWidgets(
      'legacy version menu previews upgrade and cancel preserves original parameters',
      (tester) async {
    final before = ExportRecipe(
        frame: FrameStyle.none,
        edits: const PhotoEdits()
            .copyWith(processVersion: 1)
            .withValue(PhotoAdjustment.exposure, .7));
    final (_, container) = await pumpEditor(tester, initialRecipe: before);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, '新版调色'));
    await tester.pumpAndSettle();
    expect(container.read(editorProvider(3)).recipe.edits.processVersion, 2);
    expect(find.byTooltip('重置当前工具'), findsNothing);
    expect(
        container
            .read(editorProvider(3))
            .recipe
            .edits
            .value(PhotoAdjustment.exposure),
        .7);
    await tester.tap(find.byTooltip('取消调整'));
    await tester.pumpAndSettle();
    expect(container.read(editorProvider(3)).recipe, before);
  });
  testWidgets(
      'studio preset selection stays draft until confirmed and records restore snapshots',
      (tester) async {
    final (_, container) = await pumpEditor(tester);
    final before = container.read(editorProvider(3)).recipe;
    await tester.tap(find.byKey(const ValueKey('studio-tab-0')));
    await tester.pumpAndSettle();
    final id = container.read(editorProvider(3)).luts.first.id;
    await tester.tap(find.byKey(ValueKey('lut-$id')));
    await tester.pumpAndSettle();
    expect(container.read(editorProvider(3)).recipe.lutId, id);
    await tester.tap(find.byKey(ValueKey('lut-$id')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lut-strength')), findsOneWidget);
    final name = container.read(editorProvider(3)).luts.first.name;
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('lut-$id')), findsOneWidget);

    expect(find.byKey(const ValueKey('studio-tab-1')), findsNothing);
    await tester.tap(find.byTooltip('取消调整'));
    await tester.pumpAndSettle();
    expect(container.read(editorProvider(3)).recipe, before);
    final controller = container.read(editorProvider(3).notifier);
    controller.setEdits(before.edits.withValue(PhotoAdjustment.exposure, 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开时'));
    await tester.pumpAndSettle();
    expect(
        container
            .read(editorProvider(3))
            .recipe
            .edits
            .value(PhotoAdjustment.exposure),
        0);
    expect(container.read(editorProvider(3)).canRedo, isTrue);
  });
  testWidgets('tool ribbon opens adjustments and cancel restores the photo',
      (tester) async {
    final (_, container) = await pumpEditor(tester);
    expect(find.byKey(const ValueKey('editor-tool-ribbon')), findsOneWidget);
    await tester.tap(find.text('调整图片'));
    await tester.pumpAndSettle();
    final slider = find.byType(Slider).first;
    await tester.dragFrom(tester.getCenter(slider), const Offset(72, 0));
    await tester.pumpAndSettle();
    expect(
        container
            .read(editorProvider(3))
            .recipe
            .edits
            .value(PhotoAdjustment.exposure),
        greaterThan(.5));
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
    expect(find.text('R003.JPG'), findsNothing);
    await openTab(tester, '信息');
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
    await openTab(tester, '调整图片');
    final photo = find.byKey(const ValueKey('frame-preview'));
    final start = tester.getCenter(photo);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, 24));
    await gesture.moveBy(const Offset(0, 32));
    await tester.pump();
    expect(
        find.byKey(
            const ValueKey(('editor-parameter', PhotoAdjustment.contrast))),
        findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('对比度'), findsOneWidget);
    final selector = find.byKey(const ValueKey('adjustment-parameters'));
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find
        .byKey(const ValueKey(('editor-parameter', PhotoAdjustment.contrast))));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const ValueKey('frame-preview')), const Offset(50, 0));
    await tester.pumpAndSettle();
    final e = c.read(editorProvider(3)).recipe.edits;
    expect(e.value(PhotoAdjustment.exposure), 0);
    expect(e.value(PhotoAdjustment.contrast), greaterThan(.1));
    await tester.tap(find.byTooltip('完成调整'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '导出'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(env.engine.jobs.last.adjustments![2],
        closeTo(e.value(PhotoAdjustment.contrast), .00001));
    expect(find.byKey(const ValueKey('editor-tool-ribbon')), findsOneWidget);
  });

  testWidgets('curve overlay owns vertical drags without moving the photo',
      (tester) async {
    final (_, c) = await pumpEditor(tester);
    await openTab(tester, '曲线');
    final graph = find.byKey(const ValueKey('curve-graph'));
    final photo = find.byKey(const ValueKey('frame-preview'));
    final plot = tester.getRect(graph);
    final frame = tester.getRect(photo);
    expect(plot.width, plot.height);
    expect(plot.overlaps(frame), isTrue);

    await tester.tapAt(plot.center);
    await tester.pump();
    await tester.dragFrom(plot.center, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(c.read(editorProvider(3)).recipe.edits.curves.first.points[1].y,
        greaterThan(.6));
    expect(tester.getRect(graph), plot);
    expect(tester.getRect(photo), frame);
    await tester.tap(find.byTooltip('取消调整'));
    await tester.pumpAndSettle();
    expect(
        c.read(editorProvider(3)).recipe.edits.curves.first, const ToneCurve());
  });

  testWidgets('landscape large text keeps apply and crop reachable',
      (tester) async {
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpEditor(tester, size: const Size(844, 390));
    await openTab(tester, '裁切');
    expect(find.byTooltip('完成调整'), findsOneWidget);
    await tester.ensureVisible(find.text('正方形'));
    await tester.tap(find.text('正方形'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('完成调整'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'failed autosave blocks leaving and keeps current edits available',
      (tester) async {
    final (env, c) = await pumpEditor(tester);
    final nav = Navigator.of(tester.element(find.byType(EditorPage)));
    nav.push(
        MaterialPageRoute<void>(builder: (_) => const EditorPage(mediaId: 3)));
    await tester.pumpAndSettle();
    expect(nav.canPop(), isTrue);
    await env.db.execute(
        "CREATE TRIGGER reject_edit BEFORE INSERT ON edit_documents BEGIN SELECT RAISE(FAIL, 'disk full'); END");
    final editor = c.read(editorProvider(3).notifier);
    editor.setEdits(const PhotoEdits().withValue(PhotoAdjustment.exposure, .7));
    await tester.pumpAndSettle();
    await editor.flushEdits();
    await tester.tap(find.byTooltip('返回相册'));
    await tester.pumpAndSettle();
    expect(nav.canPop(), isTrue);
    expect(
        c.read(editorProvider(3)).recipe.edits.value(PhotoAdjustment.exposure),
        .7);
    expect(find.textContaining('尚未保存'), findsOneWidget);
    await env.db.execute('DROP TRIGGER reject_edit');
    await editor.retrySave();
    await tester.tap(find.byTooltip('返回相册'));
    await tester.pumpAndSettle();
    expect(nav.canPop(), isFalse);
  });

  testWidgets(
      'date switch and border width slider produce real standalone edits',
      (tester) async {
    final (_, c) = await pumpEditor(tester);
    await openTab(tester, '日期印记');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(c.read(editorProvider(3)).recipe.dateStamp, isTrue);
    await tester.tap(find.byTooltip('完成调整'));
    await tester.pumpAndSettle();
    await openTab(tester, '边框');
    await tester.tap(find.text('等宽白边'));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(.035);
    slider.onChanged!(.08);
    slider.onChangeEnd!(.08);
    await tester.pumpAndSettle();
    expect(c.read(editorProvider(3)).recipe.frameWidth, .08);
  });
  testWidgets('leaving locks export and tools until pending save completes',
      (tester) async {
    final gate = Completer<void>();
    final (env, c) = await pumpEditor(tester, saveGate: gate.future);
    final nav = Navigator.of(tester.element(find.byType(EditorPage)));
    nav.push(
        MaterialPageRoute<void>(builder: (_) => const EditorPage(mediaId: 3)));
    await tester.pumpAndSettle();
    c
        .read(editorProvider(3).notifier)
        .setEdits(const PhotoEdits().withValue(PhotoAdjustment.exposure, .7));
    await tester.pump();
    await tester.tap(find.byTooltip('返回相册'));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '导出'))
            .onPressed,
        isNull);
    final absorbing = tester.widget<AbsorbPointer>(find
        .descendant(
            of: find.byType(EditorPage), matching: find.byType(AbsorbPointer))
        .first);
    expect(absorbing.absorbing, isTrue);
    gate.complete();
    await tester.pumpAndSettle();
    expect(nav.canPop(), isFalse);
    expect(
        (await env.store.loadEdit(3))!
            .recipe
            .edits
            .value(PhotoAdjustment.exposure),
        .7);
  });
}
