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
  testWidgets('fixed street cover never reads album or opens cover manager',
      (t) async {
    var coverReads = 0;
    final gateway = _CountThumbnails();
    await t.pumpWidget(ProviderScope(overrides: [
      mediaGatewayProvider.overrideWithValue(gateway),
      homeCoverDataProvider.overrideWith((ref) async {
        coverReads++;
        throw StateError('homepage must not request user covers');
      }),
    ], child: const MaterialApp(home: Scaffold(body: HomeCover()))));
    await t.pumpAndSettle();
    expect(coverReads, 0);
    expect(gateway.calls, 0);
    expect(find.text('街头'), findsOneWidget);
    expect(find.text('让平凡的日子，\n留下不平凡的眼光。'), findsOneWidget);
    final image = t.widget<Image>(find.byType(Image));
    expect(
        (image.image as AssetImage).assetName, 'assets/images/home_header.jpg');
    await t.longPress(find.byType(HomeCover));
    await t.drag(find.byType(HomeCover), const Offset(-200, 0));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(const Duration(seconds: 16));
    await t.pumpAndSettle();
    expect(find.byType(HomeCoverManager), findsNothing);
    expect(coverReads, 0);
    expect(find.text('街头'), findsOneWidget);
    expect(t.takeException(), isNull);
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
