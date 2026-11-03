import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/darkroom/lut/lut_library.dart';
import 'package:gremote/features/darkroom/editor/editor_controller.dart';
import 'package:gremote/features/darkroom/editor/editor_page.dart';
import 'package:gremote/imaging/gpu/gpu_editor.dart';

import '../support/fake_media_gateway.dart';
import '../support/test_darkroom.dart';

class _GatedLibrary extends LutLibrary {
  _GatedLibrary(TestDarkroom env, this.gate)
      : super(
            store: env.store, engine: env.engine, dataDir: () async => env.dir);
  final Completer<List<LutEntry>> gate;
  @override
  Future<List<LutEntry>> entries() => gate.future;
}

class _GatedLocationGateway extends FakeMediaGateway {
  _GatedLocationGateway(this.gate)
      : super(entries: [mediaEntry(3)], exif: {3: grMeta()});
  final Completer<bool> gate;
  @override
  Future<bool> hasLocationAccess() => gate.future;
}

void main() {
  for (final dependency in ['LUT catalog', 'location access']) {
    testWidgets('first photo does not wait for $dependency', (tester) async {
      final catalog = Completer<List<LutEntry>>();
      final location = Completer<bool>();
      final env =
          await TestDarkroom.create(gateway: _GatedLocationGateway(location));
      final c = ProviderContainer(overrides: [
        ...env.overrides,
        lutLibraryProvider.overrideWithValue(_GatedLibrary(env, catalog)),
      ]);
      await c.read(localMediaRepositoryProvider).scan().drain<void>();
      c.listen(editorProvider(3), (_, __) {});
      if (dependency == 'LUT catalog') location.complete(true);
      if (dependency == 'location access') catalog.complete([]);
      await tester.pumpAndSettle();
      expect(c.read(editorProvider(3)).graded, isNotNull);
      expect(c.read(editorProvider(3)).error, isNull);
      if (!catalog.isCompleted) catalog.complete([]);
      if (!location.isCompleted) location.complete(true);
      await tester.pumpAndSettle();
      expect(c.read(editorProvider(3)).locationAccess, isTrue);
      c.dispose();
      await env.close();
    });
  }

  testWidgets('cached source thumbnail is visible while editor is loading',
      (tester) async {
    const channel = MethodChannel('gremote/editor_loading_test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final opened = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'open') return opened.future;
      if (call.method == 'histogram') return null;
      if (call.method == 'update') {
        final data = Map<Object?, Object?>.from(call.arguments as Map);
        scheduleMicrotask(() => messenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(MethodCall('frame', {
              'sessionId': 1,
              'generation': data['generation'],
              'width': data['width'],
              'height': data['height'],
            })),
            (_) {}));
      }
      return true;
    });
    final gpu = GpuEditor(channel: channel, closeFd: (_) {});
    final env = await TestDarkroom.create(
        gateway:
            FakeMediaGateway(entries: [mediaEntry(3)], exif: {3: grMeta()}));
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS0UAAAAASUVORK5CYII=');
    final c = ProviderContainer(overrides: [
      ...env.overrides,
      gpuEditorProvider.overrideWithValue(gpu),
      thumbnailProvider(3).overrideWith((ref) async => bytes),
    ]);
    await c.read(localMediaRepositoryProvider).scan().drain<void>();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: EditorPage(mediaId: 3))));
    await tester.pumpAndSettle();
    final image = find.byKey(const ValueKey('editor-loading-thumbnail'));
    expect(image, findsOneWidget);
    expect((tester.widget<Image>(image).image as MemoryImage).bytes, bytes);
    expect(find.text('正在载入编辑…'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '导出'))
            .onPressed,
        isNull);
    opened.complete({
      'sessionId': 1,
      'textureId': 9,
      'sourceWidth': 6000,
      'sourceHeight': 4000,
      'capabilities': '{}',
    });
    await tester.pumpAndSettle();
    expect(image, findsNothing);
    expect(find.text('正在载入编辑…'), findsNothing);
    expect(find.byType(Texture), findsOneWidget);
    expect(c.read(editorProvider(3)).base, isNull);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '导出'))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    gpu.dispose();
    await env.close();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
