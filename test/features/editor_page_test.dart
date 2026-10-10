import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/darkroom/frame/frame_layout.dart';
import 'package:gremote/darkroom/lut/builtin_looks.dart';
import 'package:gremote/darkroom/model/edit_document.dart';
import 'package:gremote/features/darkroom/editor/editor_controller.dart';
import 'package:gremote/features/darkroom/editor/editor_page.dart';
import 'package:gremote/features/darkroom/editor/widgets/editor_panels.dart';

import '../support/fake_media_gateway.dart';
import '../support/test_darkroom.dart';

Future<(TestDarkroom, ProviderContainer)> pumpEditor(WidgetTester tester,
    {bool locationAccess = true}) async {
  tester.view.physicalSize = const Size(390, 844);
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
    child:
        MaterialApp(theme: GRemoteTheme.dark, home: const EditorPage(mediaId: 3)),
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
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('decodes a preview of the photo on open', (tester) async {
    final (env, _) = await pumpEditor(tester);
    expect(find.byKey(const ValueKey('frame-preview')), findsOneWidget);
    expect(env.engine.decoded, env.gateway.openedFds);
    expect(find.text('R003.JPG'), findsOneWidget);
  });

  testWidgets('choosing a LUT grades the preview', (tester) async {
    final (env, _) = await pumpEditor(tester);
    await tester.tap(find.text(builtinLooks.first.name));
    await tester.pumpAndSettle();
    expect(env.engine.lutCalls, [1.0]);
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

  testWidgets('hidden fields disappear from the frame', (tester) async {
    final (_, container) = await pumpEditor(tester);
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
    expect(find.textContaining('媒体位置'), findsOneWidget);
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
}
