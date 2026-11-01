import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gremote/film/catalog/official_film_library.dart';

void main() {
  test('failed sync leaves the previous offline library intact', () async {
    final dir = Directory.systemTemp.createTempSync('official-films-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final cache = File('${dir.path}/official-library.json');
    cache.writeAsStringSync('previous');
    final library = OfficialFilmLibrary(
        client: MockClient((_) async => http.Response('offline', 503)),
        directory: () async => dir);
    await expectLater(
        library.sync(expectedRenderer: 'a' * 64), throwsA(isA<Exception>()));
    expect(cache.readAsStringSync(), 'previous');
  });
  test('catalogue rejects duplicate IDs and external image hosts', () {
    Map<String, dynamic> film(String url) =>
        {'id': 33, 'name': '800T', 'group': 'ECN2', 'icon_url': url};
    expect(() => OfficialFilm.parse(film('https://other.test/p.jpg')),
        throwsFormatException);
    expect(
        () => parseOfficialCatalog(jsonEncode({
              'film_count': 2,
              'films': [film('/gr3/a.png'), film('/gr3/a.png')]
            })),
        throwsFormatException);
  });
  test('truncated and corrupt SD libraries are rejected before caching', () {
    expect(() => validateOfficialPack(List.filled(4096, 0), {33}),
        throwsFormatException);
  });
}
