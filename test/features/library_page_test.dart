import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/darkroom/model/photo_meta.dart';
import 'package:gremote/features/library/library_page.dart';
import 'package:gremote/media/local/media_gateway.dart';

import '../support/fake_media_gateway.dart';
import '../support/test_darkroom.dart';

Future<TestDarkroom> pumpLibrary(WidgetTester tester,
    {required FakeMediaGateway gateway}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final env = await TestDarkroom.create(gateway: gateway);
  addTearDown(env.close);
  final router = GoRouter(initialLocation: '/library', routes: [
    GoRoute(path: '/library', builder: (_, __) => const LibraryPage()),
    GoRoute(
        path: '/edit/:id',
        builder: (_, state) => Text('edit ${state.pathParameters['id']}')),
    GoRoute(path: '/export-queue', builder: (_, __) => const Text('queue')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: env.overrides,
    child: MaterialApp.router(theme: GRemoteTheme.dark, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return env;
}

FakeMediaGateway library({MediaAccess access = MediaAccess.granted}) =>
    FakeMediaGateway(
      mediaAccess: access,
      entries: [mediaEntry(1), mediaEntry(2), mediaEntry(3)],
      exif: {
        1: grMeta(),
        2: const PhotoMeta(width: 4000, height: 3000, model: 'Pixel 8'),
        3: grMeta(),
      },
    );

Finder tile(int id) => find.byKey(ValueKey('media-$id'));

void main() {
  testWidgets('asks for photo access before scanning', (tester) async {
    final gateway = library(access: MediaAccess.denied)
      ..accessAfterRequest = MediaAccess.granted;
    await pumpLibrary(tester, gateway: gateway);
    expect(find.text('允许访问照片'), findsOneWidget);
    expect(gateway.exifRequests, isEmpty);

    await tester.tap(find.text('允许访问照片'));
    await tester.pumpAndSettle();
    expect(tile(1), findsOneWidget);
  });

  testWidgets('partial access shows how to add more photos', (tester) async {
    await pumpLibrary(tester, gateway: library(access: MediaAccess.partial));
    expect(find.text('仅显示你允许的照片 · 继续添加'), findsOneWidget);
  });

  testWidgets('shows scan progress while EXIF is read', (tester) async {
    final gate = Completer<void>();
    final gateway = library()..beforeExif = () => gate.future;
    await pumpLibrary(tester, gateway: gateway);
    expect(find.textContaining('正在读取 EXIF'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('filters GR III by default and can show everything',
      (tester) async {
    await pumpLibrary(tester, gateway: library());
    expect(tile(1), findsOneWidget);
    expect(tile(3), findsOneWidget);
    expect(tile(2), findsNothing);

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(tile(2), findsOneWidget);
  });

  testWidgets('long press starts multi-select for batch export',
      (tester) async {
    await pumpLibrary(tester, gateway: library());
    await tester.longPress(tile(3));
    await tester.pumpAndSettle();
    expect(find.text('批量出图 (1)'), findsOneWidget);
    await tester.tap(tile(1));
    await tester.pumpAndSettle();
    expect(find.text('批量出图 (2)'), findsOneWidget);

    await tester.tap(find.text('批量出图 (2)'));
    await tester.pumpAndSettle();
    expect(find.text('默认方案'), findsOneWidget);
    await tester.tap(find.text('默认方案'));
    await tester.pumpAndSettle();
    expect(find.text('queue'), findsOneWidget);
  });

  testWidgets('tapping a photo opens the editor', (tester) async {
    await pumpLibrary(tester, gateway: library());
    await tester.tap(tile(3));
    await tester.pumpAndSettle();
    expect(find.text('edit 3'), findsOneWidget);
  });

  testWidgets('camera segment explains the connection requirement',
      (tester) async {
    await pumpLibrary(tester, gateway: library());
    await tester.tap(find.text('相机'));
    await tester.pumpAndSettle();
    expect(find.text('等待 GR III 连接'), findsOneWidget);
  });

  testWidgets('returning from camera rescans newly saved local photos',
      (tester) async {
    final gateway = library();
    await pumpLibrary(tester, gateway: gateway);
    await tester.tap(find.text('相机'));
    await tester.pumpAndSettle();
    gateway.entries = [...gateway.entries, mediaEntry(4)];
    gateway.exif = {...gateway.exif, 4: grMeta()};
    await tester.tap(find.text('本机'));
    await tester.pumpAndSettle();
    expect(tile(4), findsOneWidget);
  });
}
