import 'dart:convert';
import 'dart:io';
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
  for (final scenario in [(false, 33), (true, 33), (true, 326), (true, 327)]) {
    final (compatible, id) = scenario;
    testWidgets(
        'official detail install gate respects renderer compatibility $compatible, film $id',
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
          compatible && (id == 33 || id == 326));
      await tester.tap(find.text('800T'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('装入相机'), 200,
          scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
      final button = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '装入相机'));
      expect(button.onPressed != null, compatible && (id == 33 || id == 326));
      if (!compatible) {
        expect(find.text('胶卷版本与当前机身不匹配'), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
