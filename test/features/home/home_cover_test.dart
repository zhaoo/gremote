import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/features/home/widgets/home_cover.dart';
import 'package:gremote/features/home/home_cover_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gremote/features/home/home_cover_manager.dart';
import 'package:gremote/features/home/home_cover_providers.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/media/local/local_media_repository.dart';
import '../../support/fake_media_gateway.dart';

void main() {
  testWidgets('recent source uses independent recent frames before reordering',
      (t) async {
    final gateway = _ValidThumbnails();
    CoverFrame frame(int id) => CoverFrame(
        entry: HomeCoverEntry(id: id, uri: 'image:$id'), bytes: gateway.bytes);
    final data = HomeCoverData(
        settings: const HomeCoverSettings(
            entries: [HomeCoverEntry(id: 99, uri: 'image:99')]),
        available: [
          for (final i in [1, 2, 99])
            LocalMediaItem(
                id: i, uri: 'image:$i', displayName: '$i.jpg', dateModified: i)
        ],
        frames: [
          frame(99)
        ],
        recentFrames: [
          frame(1),
          frame(2)
        ]);
    await t.pumpWidget(ProviderScope(overrides: [
      mediaGatewayProvider.overrideWithValue(gateway),
      homeCoverDataProvider.overrideWith((ref) async => data)
    ], child: MaterialApp(home: Scaffold(body: HomeCoverManager(data: data)))));
    await t.pumpAndSettle();
    await t.tap(find.text('最近导入'));
    await t.pump();
    final rows = find.byType(ListTile);
    expect(
        find.descendant(of: rows, matching: find.text('99.jpg')), findsNothing);
    expect(find.descendant(of: rows, matching: find.text('1.jpg')),
        findsOneWidget);
    await t.tap(find.byTooltip('前移').last);
    await t.pump();
    expect(find.descendant(of: rows.at(1), matching: find.text('2.jpg')),
        findsOneWidget);
  });
  testWidgets('default mode then selecting photo begins a new manual selection',
      (t) async {
    final data = HomeCoverData(
        settings: const HomeCoverSettings(
            entries: [HomeCoverEntry(id: 1, uri: 'image:1')]),
        available: [
          const LocalMediaItem(
              id: 1, uri: 'image:1', displayName: 'one.jpg', dateModified: 1)
        ],
        frames: []);
    await t.pumpWidget(ProviderScope(overrides: [
      mediaGatewayProvider.overrideWithValue(_CountThumbnails()),
      homeCoverDataProvider.overrideWith((ref) async => data)
    ], child: MaterialApp(home: Scaffold(body: HomeCoverManager(data: data)))));
    await t.pumpAndSettle();
    await t.tap(find.text('默认街景'));
    await t.pump();
    await t.tap(find.bySemanticsLabel('one.jpg'));
    await t.pump();
    expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '默认街景')).selected,
        false);
    expect(find.text('已选 1 / 5 · 单张即固定封面'), findsOneWidget);
  });
  testWidgets('framing preview matches narrow home aspect', (t) async {
    t.view.physicalSize = const Size(320, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final gateway = _ValidThumbnails();
    final frame = CoverFrame(
        entry: const HomeCoverEntry(id: 1, uri: 'image:1'),
        bytes: gateway.bytes);
    final data = HomeCoverData(settings: const HomeCoverSettings(), available: [
      const LocalMediaItem(
          id: 1, uri: 'image:1', displayName: 'one.jpg', dateModified: 1)
    ], frames: [
      frame
    ]);
    await t.pumpWidget(ProviderScope(overrides: [
      mediaGatewayProvider.overrideWithValue(gateway),
      homeCoverDataProvider.overrideWith((ref) async => data)
    ], child: const MaterialApp(home: Scaffold(body: HomeCover()))));
    await t.pumpAndSettle();
    await t.longPress(find.byType(CoverCarousel));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('调整取景位置'));
    await t.pumpAndSettle();
    expect(t.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        closeTo(320 / 232, .001));
  });
  testWidgets('open manager stays paused across background and resume',
      (t) async {
    final gateway = _ValidThumbnails();
    final frames = [
      for (var i = 1; i <= 2; i++)
        CoverFrame(
            entry: HomeCoverEntry(id: i, uri: 'image:$i'), bytes: gateway.bytes)
    ];
    final data = HomeCoverData(
        settings: const HomeCoverSettings(),
        available: [
          for (var i = 1; i <= 2; i++)
            LocalMediaItem(
                id: i, uri: 'image:$i', displayName: '$i.jpg', dateModified: i)
        ],
        frames: frames);
    await t.pumpWidget(ProviderScope(overrides: [
      mediaGatewayProvider.overrideWithValue(gateway),
      homeCoverDataProvider.overrideWith((ref) async => data)
    ], child: const MaterialApp(home: Scaffold(body: HomeCover()))));
    await t.pumpAndSettle();
    await t.longPress(find.byType(CoverCarousel));
    await t.pumpAndSettle();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 9));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('1 / 2'), findsOneWidget);
    Navigator.of(t.element(find.byType(HomeCoverManager))).pop();
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 7));
    expect(find.text('1 / 2'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('2 / 2'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('large album only requests visible manager thumbnails',
      (t) async {
    final gateway = _CountThumbnails();
    final data = HomeCoverData(settings: const HomeCoverSettings(), available: [
      for (var i = 0; i < 1000; i++)
        LocalMediaItem(
            id: i, uri: 'image:$i', displayName: '$i.jpg', dateModified: i)
    ], frames: []);
    await t.pumpWidget(ProviderScope(overrides: [
      mediaGatewayProvider.overrideWithValue(gateway),
      homeCoverDataProvider.overrideWith((ref) async => data)
    ], child: MaterialApp(home: Scaffold(body: HomeCoverManager(data: data)))));
    await t.pumpAndSettle();
    expect(gateway.calls, lessThan(50));
    expect(t.takeException(), isNull);
  });
  final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
  Widget app({bool visible = true, bool motion = false, int count = 2}) =>
      MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(disableAnimations: motion),
              child: Scaffold(
                  body: CoverCarousel(
                frames: [
                  for (var i = 0; i < count; i++)
                    CoverFrame(
                        entry: HomeCoverEntry(id: i, uri: 'image:$i'),
                        bytes: bytes)
                ],
                autoplay: true,
                visible: visible,
                onManage: () async {},
              ))));
  testWidgets('works show no slogan and advance after eight seconds',
      (t) async {
    await t.pumpWidget(app());
    expect(find.text('街头'), findsNothing);
    expect(find.text('1 / 2'), findsOneWidget);
    await t.pump(const Duration(seconds: 7));
    expect(find.text('1 / 2'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('2 / 2'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('hidden view and reduced motion do not auto advance', (t) async {
    await t.pumpWidget(app(visible: false));
    await t.pump(const Duration(seconds: 16));
    expect(find.text('1 / 2'), findsOneWidget);
    await t.pumpWidget(app(motion: true));
    await t.pump(const Duration(seconds: 16));
    expect(find.text('1 / 2'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('touch pauses and restarts a full interval', (t) async {
    await t.pumpWidget(app());
    await t.pump(const Duration(seconds: 7));
    final g = await t.startGesture(t.getCenter(find.byType(CoverCarousel)));
    await t.pump(const Duration(seconds: 2));
    expect(find.text('1 / 2'), findsOneWidget);
    await g.up();
    await t.pump(const Duration(seconds: 7));
    expect(find.text('1 / 2'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('2 / 2'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('empty or unreadable source falls back to default cover',
      (t) async {
    await t.pumpWidget(app(count: 0));
    expect(find.text('街头'), findsOneWidget);
    expect(find.text('1 / 2'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}

class _CountThumbnails extends FakeMediaGateway {
  int calls = 0;
  @override
  Future<Uint8List?> thumbnail(int id, int edge) async {
    calls++;
    return null;
  }
}

class _ValidThumbnails extends FakeMediaGateway {
  final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
  @override
  Future<Uint8List?> thumbnail(int id, int edge) async => bytes;
}
