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
