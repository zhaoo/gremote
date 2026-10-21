// Opt-in host rendering evidence, not camera/device evidence.
// flutter test --dart-define=FILM_VISUALS=true test/features/film_workbench_visual_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/features/film_workbench/film_workbench_page.dart';
import 'package:gremote/features/film_workbench/workbench_providers.dart';
import 'package:gremote/film/model/film_recipe.dart';
import 'package:gremote/film/preview/film_preview_engine.dart';
import 'package:gremote/imaging/imaging_engine.dart';
import 'package:gremote/storage/gremote_database.dart';

class _ObservedRealEngine implements FilmPreviewEngine {
  final ready = Completer<void>();
  final engine = const FfiFilmPreviewEngine(
      libraryPath: 'native/imaging/build/host/libgremote_imaging.dylib');
  @override
  Future<FilmPreviewResult> render(
      {required PreviewImage source,
      required FilmRecipe recipe,
      required PreviewStage stage,
      required int generation,
      ImagingCancelToken? cancel,
      int maxEdge = 960}) async {
    final result = await engine.render(
        source: source,
        recipe: recipe,
        stage: stage,
        generation: generation,
        cancel: cancel,
        maxEdge: maxEdge);
    if (!ready.isCompleted) ready.complete();
    return result;
  }
}

void main() {
  testWidgets('capture real Flutter workbench surfaces', (tester) async {
    final fontPath = Platform.environment['FILM_VISUAL_FONT'];
    if (fontPath != null) {
      await tester.runAsync(() async {
        final bytes = await File(fontPath).readAsBytes();
        for (final family in [
          'Roboto',
          'Ahem',
          'PingFang SC',
          'Noto Sans CJK SC'
        ]) {
          final loader = FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
        }
        final icons =
            await File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
                .readAsBytes();
        final loader = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(icons)));
        await loader.load();
      });
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sqfliteFfiInit();
    final db = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    addTearDown(db.close);
    final engine = _ObservedRealEngine(), key = GlobalKey();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          filmPreviewEngineProvider.overrideWithValue(engine)
        ],
        child: RepaintBoundary(
            key: key,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: GRemoteTheme.dark.copyWith(
                    textTheme: GRemoteTheme.dark.textTheme
                        .apply(fontFamily: "Roboto")),
                home: const FilmWorkbenchPage()))));
    for (var attempt = 0;
        attempt < 200 && !engine.ready.isCompleted;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(engine.ready.isCompleted, isTrue,
        reason: 'Real sample decode and FFI render must finish');
    // Flush the platform image callbacks and actual asset decoding before capture.
    for (var frame = 0; frame < 10; frame++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    Future<void> save(String name) async {
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('docs/design/film-workbench/2026-10-21-flutter-$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    await save('trial');
    await tester.tap(find.text('数字胶卷'));
    await tester.pumpAndSettle();
    await save('rolls-empty');
    await tester.tap(find.text('相机胶卷'));
    await tester.pumpAndSettle();
    await save('camera-offline');
    expect(tester.takeException(), isNull);
  }, skip: !const bool.fromEnvironment('FILM_VISUALS'));
}
