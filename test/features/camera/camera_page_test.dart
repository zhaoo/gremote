import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/features/camera/camera_page.dart';
import 'package:gremote/features/camera/film_library_page.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import '../../support/test_darkroom.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets(
        'camera workspace fits $width with large text and searchable film grid',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
          tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
      final env = await TestDarkroom.create();
      addTearDown(env.close);
      final catalog = await tester.runAsync(() async =>
          CameraFilmCatalog.fromJson(jsonDecode(await rootBundle.loadString(
              'assets/films/camera-catalog.json')) as Map<String, dynamic>));
      await tester.pumpWidget(ProviderScope(
          overrides: [
            ...env.overrides,
            cameraFilmCatalogProvider.overrideWith((_) async => catalog!),
            officialFilmCacheProvider.overrideWith((_) async => null)
          ],
          child:
              MaterialApp(theme: GRemoteTheme.dark, home: const CameraPage())));
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      await tester.tap(find.byTooltip('搜索胶卷'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '800T');
      await tester.pumpAndSettle();
      expect(find.text('800T', findRichText: false).last, findsOneWidget);
      expect(find.text('Portra 400'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('扩展'));
      await tester.pumpAndSettle();
      expect(find.text('未连接 · 配对 M10V 后可设置'), findsOneWidget);
      expect(find.text('HDF'), findsNothing);
      expect(find.widgetWithText(TextButton, '重新读取'), findsNothing);
      for (final group in ['功能', '效果', '水印', '焦距', '画幅']) {
        expect(find.byKey(ValueKey('extension-group-$group')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('extension-group-效果')));
      await tester.pumpAndSettle();
      final hdf = tester
          .widget<ListTile>(find.byKey(const ValueKey('extension-field-hdf')));
      expect(hdf.enabled, isFalse);
      expect(hdf.onTap, isNull);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('extension-field-hdf')),
              matching: find.text('—')),
          findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      // Inspecting the connection choices remains available while writes are gated.
      await tester.tap(find.text('未连接'));
      await tester.pumpAndSettle();
      expect(
          tester.widget<ListTile>(find.widgetWithText(ListTile, '相机连接')).onTap,
          isNotNull);
      expect(
          tester
              .widget<ListTile>(find.widgetWithText(ListTile, '配对与机内胶卷'))
              .onTap,
          isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
}
