import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/darkroom/lut/cube_writer.dart';
import 'package:gremote/darkroom/model/edit_document.dart';
import 'package:gremote/darkroom/model/export_recipe.dart';
import 'package:gremote/features/darkroom/darkroom_controller.dart';
import 'package:gremote/features/darkroom/darkroom_page.dart';
import 'package:gremote/imaging/imaging_exception.dart';

import '../support/test_darkroom.dart';

class FakeLutFilePicker implements LutFilePicker {
  (String, Uint8List)? value;
  int calls = 0;

  @override
  Future<(String name, Uint8List bytes)?> pick() async {
    calls++;
    return value;
  }
}

Future<(TestDarkroom, FakeLutFilePicker)> pumpDarkroom(
    WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final env = await TestDarkroom.create();
  addTearDown(env.close);
  final picker = FakeLutFilePicker();
  final router = GoRouter(initialLocation: '/darkroom', routes: [
    GoRoute(path: '/darkroom', builder: (_, __) => const DarkroomPage()),
    GoRoute(
        path: '/edit/:id',
        builder: (_, state) => Text('edit ${state.pathParameters['id']}')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...env.overrides,
      lutFilePickerProvider.overrideWithValue(picker),
    ],
    child: MaterialApp.router(theme: GRemoteTheme.dark, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (env, picker);
}

Uint8List cube(int size) => Uint8List.fromList(
    writeCube(title: 'test', size: size, map: (r, g, b) => [r, g, b])
        .codeUnits);

void main() {
  testWidgets('lists recent edits and opens one', (tester) async {
    final env = await TestDarkroom.create();
    await env.store.saveEdit(EditDocument(
        mediaId: 3, title: '清晨', updatedAt: DateTime(2026, 10, 10)));
    final picker = FakeLutFilePicker();
    addTearDown(env.close);
    final router = GoRouter(initialLocation: '/darkroom', routes: [
      GoRoute(path: '/darkroom', builder: (_, __) => const DarkroomPage()),
      GoRoute(
          path: '/edit/:id',
          builder: (_, state) => Text('edit ${state.pathParameters['id']}')),
    ]);
    await tester.pumpWidget(ProviderScope(overrides: [
      ...env.overrides,
      lutFilePickerProvider.overrideWithValue(picker)
    ], child: MaterialApp.router(theme: GRemoteTheme.dark, routerConfig: router)));
    await tester.pumpAndSettle();

    expect(find.text('最近编辑'), findsOneWidget);
    expect(find.text('清晨'), findsOneWidget);
    await tester.tap(find.text('清晨'));
    await tester.pumpAndSettle();
    expect(find.text('edit 3'), findsOneWidget);
  });

  testWidgets('shows five builtin LUTs', (tester) async {
    await pumpDarkroom(tester);
    expect(find.text('LUT 库'), findsOneWidget);
    expect(find.byKey(const ValueKey('builtin-lut')), findsNWidgets(5));
  });

  testWidgets('bad cube import explains the reason', (tester) async {
    final (env, picker) = await pumpDarkroom(tester);
    env.engine.validateError = ImagingErrorCode.lutParse;
    picker.value =
        ('bad.cube', Uint8List.fromList('LUT_3D_SIZE 129\n'.codeUnits));
    await tester.tap(find.text('导入 LUT'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2–128'), findsOneWidget);
  });

  testWidgets('imports and deletes a LUT', (tester) async {
    final (env, picker) = await pumpDarkroom(tester);
    env.engine.lutSize = 17;
    picker.value = ('胶片.cube', cube(17));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(DarkroomPage)));
    await tester
        .runAsync(() => container.read(darkroomActionsProvider).importLut());
    await tester.pumpAndSettle();
    final imported = await tester.runAsync(env.store.importedLuts);
    expect(imported, hasLength(1));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -280));
    await tester.pumpAndSettle();
    expect(find.text('胶片'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('delete-lut')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(find.text('胶片'), findsNothing);
  });

  testWidgets('renames and deletes presets', (tester) async {
    final (env, _) = await pumpDarkroom(tester);
    final preset = await env.store.savePreset('街拍', const ExportRecipe());
    env.engine.validated.clear();
    // Notify after direct test setup write.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(DarkroomPage)));
    container.read(darkroomRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(find.text('街拍'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('rename-${preset.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '夜街');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('夜街'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('delete-${preset.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(find.text('夜街'), findsNothing);
  });
}
