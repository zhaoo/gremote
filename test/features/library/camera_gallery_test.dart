import 'dart:typed_data';
import 'dart:async';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/http/camera_api.dart';
import 'package:gremote/camera/gateway/ble_gateway.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/features/library/camera_gallery.dart';
import 'package:gremote/platform/device_api.g.dart';
import '../../support/camera_harness.dart';

class GalleryFixture extends CameraGalleryService {
  GalleryFixture(CameraApi api,
      {Stream<CameraDeviceEvent> events = const Stream.empty()})
      : super(api, CameraDeviceHostApi(), events: events);
  final downloaded = <String>[];
  Completer<String>? pending;
  @override
  Future<List<CameraFile>> photos() async => const [
        CameraFile(dir: '100RICOH', file: 'R001.JPG'),
        CameraFile(dir: '100RICOH', file: 'R001.DNG'),
        CameraFile(dir: '100RICOH', file: 'R002.JPG'),
      ];
  @override
  Future<Uint8List> thumbnail(CameraFile file) async =>
      throw StateError('no preview');
  @override
  Future<String> download(CameraFile file) async {
    downloaded.add(file.remoteId);
    if (pending != null) return pending!.future;
    if (file.file == 'R001.JPG') throw StateError('disk full');
    return 'content://saved';
  }
}

void main() {
  testWidgets(
      'explicit selection and JPEG filter save all, retain failure for retry',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = (await tester.runAsync(CameraHarness.create))!;
    addTearDown(harness.dispose);
    await tester.runAsync(harness.connect);
    final fixture = GalleryFixture(CameraApi(harness.gateways.transport));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: harness.container,
        child: ProviderScope(
            overrides: [
              cameraGalleryServiceProvider.overrideWithValue(fixture)
            ],
            child: MaterialApp(
                theme: GRemoteTheme.dark,
                home: const Scaffold(body: CameraGallery())))));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('R001'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('R001'), findsOneWidget);
    expect(find.text('R002'), findsOneWidget);
    await tester.tap(find.text('JPG').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存原图'));
    await tester.pumpAndSettle();
    expect(fixture.downloaded, ['100RICOH/R001.JPG', '100RICOH/R002.JPG']);
    expect(find.textContaining('成功 1'), findsWidgets);
    expect(find.textContaining('已选 1'), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
  for (final format in ['JPG', 'RAW', 'RAW+JPG']) {
    testWidgets('selected photo saves $format without losing its selection',
        (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = (await tester.runAsync(CameraHarness.create))!;
      addTearDown(harness.dispose);
      await tester.runAsync(harness.connect);
      final fixture = GalleryFixture(CameraApi(harness.gateways.transport));
      await tester.pumpWidget(UncontrolledProviderScope(
          container: harness.container,
          child: ProviderScope(
              overrides: [
                cameraGalleryServiceProvider.overrideWithValue(fixture)
              ],
              child: MaterialApp(
                  theme: GRemoteTheme.dark,
                  home: const Scaffold(body: CameraGallery())))));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('R001'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(format).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存原图'));
      await tester.pumpAndSettle();
      expect(
          fixture.downloaded,
          switch (format) {
            'JPG' => ['100RICOH/R001.JPG'],
            'RAW' => ['100RICOH/R001.DNG'],
            _ => ['100RICOH/R001.JPG', '100RICOH/R001.DNG'],
          });
      expect(tester.takeException(), isNull);
      if (format == 'RAW') {
        await tester.tap(find
            .ancestor(of: find.text('R001'), matching: find.byType(InkWell))
            .first);
        await tester.pumpAndSettle();
        expect(find.text('已选 0 张'), findsWidgets);
      }
    });
  }
  testWidgets(
      'stop subsequent preserves unfinished photos and finishes current original',
      (tester) async {
    final harness = (await tester.runAsync(CameraHarness.create))!;
    addTearDown(harness.dispose);
    await tester.runAsync(harness.connect);
    final fixture = GalleryFixture(CameraApi(harness.gateways.transport));
    fixture.pending = Completer<String>();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: harness.container,
        child: ProviderScope(
            overrides: [
              cameraGalleryServiceProvider.overrideWithValue(fixture)
            ],
            child: MaterialApp(
                theme: GRemoteTheme.dark,
                home: const Scaffold(body: CameraGallery())))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存原图'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('停止后续'));
    await tester.pump();
    expect(fixture.downloaded, ['100RICOH/R001.JPG']);
    fixture.pending!.complete('content://saved');
    await tester.pumpAndSettle();
    expect(fixture.downloaded, ['100RICOH/R001.JPG']);
    expect(find.textContaining('已停止'), findsOneWidget);
    expect(find.text('已选 2 张'), findsWidgets);
  });
  testWidgets(
      'tap toggles groups and disconnect clears selection and stale save',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = (await tester.runAsync(CameraHarness.create))!;
    addTearDown(harness.dispose);
    await tester.runAsync(harness.connect);
    final progress = StreamController<CameraDeviceEvent>.broadcast();
    addTearDown(progress.close);
    final fixture = GalleryFixture(CameraApi(harness.gateways.transport),
        events: progress.stream);
    fixture.pending = Completer<String>();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: harness.container,
        child: ProviderScope(
            overrides: [
              cameraGalleryServiceProvider.overrideWithValue(fixture)
            ],
            child: MaterialApp(
                theme: GRemoteTheme.dark,
                home: const Scaffold(body: CameraGallery())))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find
        .ancestor(of: find.text('R001'), matching: find.byType(InkWell))
        .first);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 张'), findsWidgets);
    await tester.tap(find
        .ancestor(of: find.text('R001'), matching: find.byType(InkWell))
        .first);
    await tester.pumpAndSettle();
    expect(find.text('已选 0 张'), findsWidgets);
    await tester.tap(find
        .ancestor(of: find.text('R001'), matching: find.byType(InkWell))
        .first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存原图'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('正在保存原图'), findsOneWidget);
    progress.add(const CameraDeviceEvent(
        type: 'photoProgress',
        jsonPayload:
            '{"id":"100RICOH/R001.JPG","bytes":524288,"total":1048576}'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('50%'), findsOneWidget);
    progress.add(const CameraDeviceEvent(
        type: 'photoProgress',
        jsonPayload:
            '{"id":"100RICOH/other.JPG","bytes":999999,"total":1048576}'));
    await tester.pump();
    expect(find.text('50%'), findsOneWidget);
    progress.add(const CameraDeviceEvent(
        type: 'photoProgress',
        jsonPayload: '{"id":"100RICOH/R001.JPG","bytes":786432,"total":-1}'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('50%'), findsNothing);
    expect(find.textContaining('文件大小未知'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const Key('photo-progress-bar')))
            .value,
        isNull);

    expect(find.text('R001'), findsOneWidget);
    expect(tester.getRect(find.text('正在保存原图')).top,
        greaterThan(tester.getRect(find.text('已选 1 张').first).bottom));
    await tester.runAsync(() =>
        harness.container.read(connectionControllerProvider.notifier).cancel());
    await tester.pumpAndSettle();
    fixture.pending!.complete('content://old-session');
    await tester.pumpAndSettle();
    expect(find.text('等待 GR III 连接'), findsOneWidget);
    await tester.runAsync(harness.connect);
    await tester.pumpAndSettle();
    expect(find.text('多选'), findsOneWidget);
    expect(find.textContaining('保存完成'), findsNothing);
    expect(fixture.downloaded, ['100RICOH/R001.JPG']);
  });
}
