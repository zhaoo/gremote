import 'dart:typed_data';
import 'dart:async';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/http/camera_api.dart';
import 'package:gremote/camera/http/camera_files.dart';
import 'package:gremote/features/library/camera_gallery.dart';
import 'package:gremote/platform/device_api.g.dart';
import '../../support/camera_harness.dart';

class GalleryFixture extends CameraGalleryService {
  GalleryFixture(CameraApi api) : super(api, CameraDeviceHostApi());
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
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('R001'), findsOneWidget);
    expect(find.text('R002'), findsOneWidget);
    await tester.tap(find.text('仅 JPEG'));
    await tester.pump();
    await tester.tap(find.text('全选'));
    await tester.pump();
    await tester.tap(find.text('保存原图'));
    await tester.pumpAndSettle();
    expect(fixture.downloaded, ['100RICOH/R001.JPG', '100RICOH/R002.JPG']);
    expect(find.textContaining('成功 1'), findsWidgets);
    expect(find.textContaining('已选 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
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
    await tester.pump();
    await tester.tap(find
        .ancestor(of: find.text('R001'), matching: find.byType(InkWell))
        .first);
    await tester.pump();
    expect(find.text('已选 2 个文件'), findsOneWidget);
    await tester.tap(find
        .ancestor(of: find.text('R001'), matching: find.byType(InkWell))
        .first);
    await tester.pump();
    expect(find.text('已选 0 个文件'), findsOneWidget);
    await tester.tap(find
        .ancestor(of: find.text('R001'), matching: find.byType(InkWell))
        .first);
    await tester.pump();
    await tester.tap(find.text('保存原图'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('正在保存原图'), findsOneWidget);
    expect(find.text('R001'), findsOneWidget);
    expect(tester.getRect(find.text('正在保存原图')).top,
        greaterThan(tester.getRect(find.text('相机照片')).bottom));
    await tester.runAsync(() =>
        harness.container.read(connectionControllerProvider.notifier).cancel());
    await tester.pump();
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
