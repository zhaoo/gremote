import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/camera/companion/extensions_controller.dart';
import 'package:gremote/features/camera/extensions_page.dart';
import 'package:gremote/features/camera/extensions_providers.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import '../../camera/extensions_controller_test.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets(
        'extension HDF save uses confirmation and real readback at $width',
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
      await tester.scrollUntilVisible(find.text('HDF'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('HDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('弱'));
      await tester.pumpAndSettle();
      expect(api.submissions, 0);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(api.submissions, 1);
      expect(controller.snapshot!.values['hdf'], 1);
      expect(find.text('已保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
