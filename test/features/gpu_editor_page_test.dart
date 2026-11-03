import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/features/darkroom/editor/editor_controller.dart';
import 'package:gremote/features/darkroom/editor/editor_page.dart';
import 'package:gremote/imaging/gpu/gpu_editor.dart';
import '../support/fake_media_gateway.dart';
import '../support/test_darkroom.dart';

void main() {
  testWidgets(
      'ready GPU frame enables the actual editor export action without CPU base',
      (tester) async {
    const channel = MethodChannel('gremote/gpu_editor_widget_test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'open') {
        return {
          'sessionId': 1,
          'textureId': 9,
          'sourceWidth': 6000,
          'sourceHeight': 4000,
          'capabilities': '{}'
        };
      }
      if (call.method == 'histogram') return null;
      if (call.method == 'update') {
        final data = Map<Object?, Object?>.from(call.arguments as Map);
        scheduleMicrotask(() => messenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(MethodCall('frame', {
              'sessionId': 1,
              'generation': data['generation'],
              'width': data['width'],
              'height': data['height']
            })),
            (_) {}));
      }
      return true;
    });
    final gpu = GpuEditor(channel: channel, closeFd: (_) {});
    final env = await TestDarkroom.create(
        gateway:
            FakeMediaGateway(entries: [mediaEntry(3)], exif: {3: grMeta()}));
    final container = ProviderContainer(overrides: [
      ...env.overrides,
      gpuEditorProvider.overrideWithValue(gpu)
    ]);
    await container.read(localMediaRepositoryProvider).scan().drain<void>();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: GRemoteTheme.dark, home: const EditorPage(mediaId: 3))));
    await tester.pumpAndSettle();
    final state = container.read(editorProvider(3));
    expect(state.base, isNull);
    expect(state.gpuFrame, isNotNull);
    final button = find.widgetWithText(FilledButton, '导出');
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(env.engine.jobs, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    gpu.dispose();
    await env.close();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
