import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:gremote/film/catalog/official_film_library.dart';
import 'package:gremote/film/catalog/official_lut_cache.dart';

void main() {
  test('real official library downloads portable phone data and exact SD pack',
      () async {
    final dir = Directory.systemTemp.createTempSync('gremote-live-official-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final client = http.Client();
    addTearDown(client.close);
    final library =
        OfficialFilmLibrary(client: client, directory: () async => dir);
    final result = await library.sync(
        expectedRenderer:
            '80a4d357be06ff0e9510a20bef1035dc3e848ec585bd5d5cdee466c3980506a4');
    final cache = OfficialLutCache(directory: () async => dir);
    final entries = await cache.entries();
    expect(entries.length, greaterThan(40));
    for (final entry in entries) {
      expect(await cache.load(entry.id), isNotEmpty);
    }
    final pack = await library.exportPack();
    expect(validateOfficialPack(pack, result.films.map((f) => f.id).toSet()),
        result.rendererHash);
    final report = File('dist/verification/library-update/live-sync.json');
    await report.parent.create(recursive: true);
    await report.writeAsString(jsonEncode({
      'films': result.films.length,
      'phoneFilms': entries.map((e) => e.filmId).toSet().length,
      'phoneVariants': entries.length,
      'packSha256': result.sha256,
      'renderer': result.rendererHash,
      'cameraCompatibleWithOld': result.cameraCompatible,
      'notPortable': result.films
          .where((f) => !entries.any((e) => e.filmId == f.id))
          .map((f) => f.id)
          .toList(),
      'cameraWrites': 0
    }));
  },
      skip: Platform.environment['M10V_LIVE_SYNC'] != '1',
      timeout: const Timeout(Duration(minutes: 3)));
}
