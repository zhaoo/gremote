import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/darkroom/lut/lut_library.dart';
import 'package:gremote/imaging/imaging_engine.dart';
import 'package:go_router/go_router.dart';
import 'package:gremote/film/catalog/official_lut_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/features/camera/camera_availability.dart';
import 'package:gremote/features/camera/film_library_page.dart';
import 'package:gremote/features/camera/widgets/film_library_tile.dart';
import 'package:gremote/features/darkroom/darkroom_controller.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';
import 'package:gremote/features/film_workbench/workbench_providers.dart';
import 'package:gremote/film/catalog/official_film_library.dart';

void main() {
  for (final scenario in [
    (false, 33),
    (false, 327),
    (true, 33),
    (true, 326),
    (true, 327)
  ]) {
    final (compatible, id) = scenario;
    testWidgets(
        'camera install uses camera catalog regardless of phone renderer $compatible, film $id',
        (tester) async {
      final catalog = CameraFilmCatalog.fromJson(jsonDecode(
          File('assets/films/camera-catalog.json').readAsStringSync()));
      final snapshot = OfficialFilmSnapshot(
        [
          OfficialFilm(
              id: id,
              name: '800T',
              group: 'ECN2',
              icon: '/gr3/film-icons/33.png')
        ],
        DateTime.utc(2026, 11, 3),
        'aa' * 32,
        rendererHash: compatible ? catalog.rendererHash : 'bb' * 32,
        cameraCompatible: compatible,
      );
      await tester.pumpWidget(ProviderScope(overrides: [
        cameraFilmCatalogProvider.overrideWith((_) async => catalog),
        officialFilmCacheProvider.overrideWith((_) async => snapshot),
        cameraAvailabilityProvider.overrideWithValue(const CameraAvailability(
            canReadFilms: false, canInstallFilms: true, hint: '')),
        darkroomOverviewProvider.overrideWith((_) async =>
            const DarkroomOverview(edits: [], luts: [], presets: [])),
        filmCatalogProvider.overrideWith(
            (_) async => throw const FormatException('No local preview')),
      ], child: const MaterialApp(home: Scaffold(body: FilmLibraryPage()))));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilmLibraryTile>(find.byType(FilmLibraryTile))
              .available,
          id == 33 || id == 326);
      await tester.tap(find.text('800T'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('装入相机'), 200,
          scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
      final button = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '装入相机'));
      expect(button.onPressed != null, id == 33 || id == 326);
      expect(find.text('胶卷版本与当前机身不匹配'), findsNothing);
      expect(find.text('装入机身版本'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'official phone edit remains available when camera version differs',
      (tester) async {
    final catalog = CameraFilmCatalog.fromJson(jsonDecode(
        File('assets/films/camera-catalog.json').readAsStringSync()));
    final id = 'official:326:default:${'11' * 32}';
    final lut = OfficialLutRecord.fromJson({
      'id': id,
      'name': 'Vista 200',
      'filmId': 326,
      'variant': 'default',
      'size': 15,
      'contentHash': '11' * 32,
      'byteLength': 200
    });
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: FilmLibraryPage())),
      GoRoute(
          path: '/library',
          builder: (_, state) =>
              Text(state.uri.queryParameters['lut'] ?? 'missing'))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      cameraFilmCatalogProvider.overrideWith((_) async => catalog),
      officialFilmCacheProvider.overrideWith((_) async => OfficialFilmSnapshot(
          [
            const OfficialFilm(
                id: 326,
                name: 'Vista 200',
                group: 'C41',
                icon: '/gr3/film-icons/326.png')
          ],
          DateTime.utc(2026),
          'aa' * 32,
          rendererHash: 'bb' * 32,
          cameraCompatible: false,
          phoneLuts: [lut])),
      cameraAvailabilityProvider.overrideWithValue(const CameraAvailability(
          canReadFilms: false, canInstallFilms: false, hint: '连接相机后装卷')),
      darkroomOverviewProvider.overrideWith((_) async =>
          const DarkroomOverview(edits: [], luts: [], presets: [])),
      lutLibraryProvider.overrideWithValue(_UnavailablePreview()),
      trialSampleLoaderProvider.overrideWithValue(
          () async => PreviewImage(width: 1, height: 1, rgba: Uint8List(4))),
      filmCatalogProvider
          .overrideWith((_) async => throw const FormatException('fixture'))
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(
        tester.widget<FilmLibraryTile>(find.byType(FilmLibraryTile)).available,
        true);
    await tester.tap(find.text('Vista 200'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('用于修图'), 150,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('用于修图'));
    await tester.pumpAndSettle();
    expect(find.text(id), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'SD library export is explicitly requested and cancellation stays quiet',
      (tester) async {
    final catalog = CameraFilmCatalog.fromJson(jsonDecode(
        File('assets/films/camera-catalog.json').readAsStringSync()));
    var calls = 0;
    await tester.pumpWidget(ProviderScope(overrides: [
      cameraFilmCatalogProvider.overrideWith((_) async => catalog),
      officialFilmCacheProvider.overrideWith((_) async => null),
      cameraAvailabilityProvider.overrideWithValue(const CameraAvailability(
          canReadFilms: false, canInstallFilms: false, hint: '')),
      darkroomOverviewProvider.overrideWith((_) async =>
          const DarkroomOverview(edits: [], luts: [], presets: [])),
      officialFilmLibraryProvider.overrideWithValue(_ExportLibrary()),
      officialFilmExportProvider.overrideWithValue((bytes) async {
        calls++;
        expect(bytes, [1, 2, 3]);
        return false;
      })
    ], child: const MaterialApp(home: Scaffold(body: FilmLibraryPage()))));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.byTooltip('导出 SD 胶卷库'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('胶卷库已导出'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _ExportLibrary extends Fake implements OfficialFilmLibrary {
  @override
  Future<Uint8List> exportPack() async => Uint8List.fromList([1, 2, 3]);
}

class _UnavailablePreview extends Fake implements LutLibrary {
  @override
  Future<Uint8List> load(String id) async =>
      throw const FormatException('fixture preview unavailable');
}
