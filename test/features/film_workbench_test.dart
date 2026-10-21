import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:gremote/film/model/film_recipe.dart';
import 'package:gremote/film/preview/film_preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/features/film_workbench/film_workbench_page.dart';
import 'package:gremote/features/film_workbench/workbench_providers.dart';
import 'package:gremote/features/film_workbench/widgets/comparison_preview.dart';
import 'package:gremote/film/catalog/film_catalog.dart';
import 'package:gremote/imaging/imaging_engine.dart';

class ObservedPreviewEngine implements FilmPreviewEngine {
  int calls = 0;
  @override
  Future<FilmPreviewResult> render(
      {required PreviewImage source,
      required FilmRecipe recipe,
      required PreviewStage stage,
      required int generation,
      ImagingCancelToken? cancel,
      int maxEdge = 960}) async {
    calls++;
    return FilmPreviewResult(
        image: source,
        recipeFingerprint: recipe.fingerprint,
        generation: generation,
        stage: stage);
  }
}

void main() {
  final catalog = FilmCatalog.fromJson(
      jsonDecode(File('assets/films/catalog.json').readAsStringSync())
          as Map<String, dynamic>);
  Future<void> show(WidgetTester tester,
      {int section = 0,
      double width = 390,
      double scale = 1,
      FilmPreviewEngine? engine,
      Future<PreviewImage> Function()? sampleLoader}) async {
    tester.view.physicalSize = Size(width, width == 320 ? 640 : 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final waiting = Completer<PreviewImage>();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          filmCatalogProvider.overrideWith((ref) async => catalog),
          trialSampleLoaderProvider
              .overrideWithValue(sampleLoader ?? () => waiting.future),
          if (engine != null)
            filmPreviewEngineProvider.overrideWithValue(engine),
          filmRollsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
            theme: GRemoteTheme.dark,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true),
                child: child!),
            home: FilmWorkbenchPage(initialSection: section))));
    await tester.pump();
    await tester.pump();
  }

  for (final width in [320.0, 390.0]) {
    testWidgets(
        'trial layout is scrollable at $width with large text and comparison drag',
        (tester) async {
      await show(tester, width: width, scale: 1.4);
      expect(find.text('试卷台'), findsWidgets);
      expect(find.byType(ComparisonPreview), findsOneWidget);
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .animationDuration,
          Duration.zero);
      await tester.drag(find.byType(ComparisonPreview), const Offset(60, 0));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('用这卷开始'), 250,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('调整质感'));
      await tester.pumpAndSettle();
      expect(find.text('颗粒'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'original and three selectable films render in bounded comparison mode',
      (tester) async {
    final engine = ObservedPreviewEngine();
    await show(tester,
        engine: engine,
        sampleLoader: () async =>
            PreviewImage(width: 2, height: 2, rgba: Uint8List(16)));
    await tester.pump();
    expect(find.text('四格对比'), findsOneWidget);
    await tester.tap(find.text('四格对比'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('film-compare-original')), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('film-compare-$i')), findsOneWidget);
    }
    expect(find.byType(ComparisonPreview), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('digital roll empty state has no fictional photos or count',
      (tester) async {
    await show(tester, section: 1);
    expect(find.text('把一天，拍成一卷。'), findsOneWidget);
    expect(find.text('新建胶卷'), findsOneWidget);
    expect(find.text('18 / 36 张'), findsNothing);
    expect(find.text('雨后散步'), findsNothing);
  });
  testWidgets('camera page is explicitly unavailable before bridge evidence',
      (tester) async {
    await show(tester, section: 2);
    expect(find.textContaining('尚未连接'), findsWidgets);
    expect(find.text('已同步'), findsNothing);
  });
  testWidgets('comparison drags never rerender while selecting a film does',
      (tester) async {
    final engine = ObservedPreviewEngine(),
        image = PreviewImage(width: 2, height: 2, rgba: Uint8List(16));
    await show(tester, engine: engine, sampleLoader: () async => image);
    await tester.pump();
    expect(engine.calls, greaterThan(0));
    final before = engine.calls;
    await tester.drag(find.byType(ComparisonPreview), const Offset(80, 0));
    await tester.pump();
    expect(engine.calls, before);
    await tester.tap(find.text('5207'));
    await tester.pump();
    expect(engine.calls, greaterThan(before));
  });
  testWidgets('sample completion after rapid exit cannot update disposed page',
      (tester) async {
    final sample = Completer<PreviewImage>();
    await show(tester, sampleLoader: () => sample.future);
    await tester.pumpWidget(const SizedBox());
    sample.complete(PreviewImage(width: 2, height: 2, rgba: Uint8List(16)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
