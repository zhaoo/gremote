import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gremote/film/catalog/official_film_library.dart';

Uint8List samplePack({int filmId = 33}) {
  final bytes = Uint8List(4096 + 12288), header = ByteData.sublistView(bytes);
  bytes.setRange(0, 8, ascii.encode('M10VSD1\x00'));
  for (final e in {
    8: 1,
    12: bytes.length,
    16: 1,
    20: 12288,
    24: 239,
    28: 1,
    64: filmId,
    72: 1
  }.entries) {
    header.setUint32(e.key, e.value, Endian.little);
  }
  final record = Uint8List.sublistView(bytes, 4096),
      data = ByteData.sublistView(record);
  record.setRange(0, 8, ascii.encode('M10VREC1'));
  data.setUint32(8, filmId, Endian.little);
  record.fillRange(8448, 8480, 0xaa);
  if (filmId == 326 || filmId == 331) {
    record.setRange(64, 96, sha256.convert(List.filled(10125, 153)).bytes);
  }
  final crc = filmCrc(record.sublist(0, 12284));
  data.setUint32(12284, crc, Endian.little);
  header.setUint32(68, crc, Endian.little);
  header.setUint32(4092, filmCrc(bytes.sublist(0, 4092)), Endian.little);
  return bytes;
}

Uint8List storedZip(Uint8List pack) {
  final name = utf8.encode('SD/M10V/FILMS.M10');
  final bytes = Uint8List(30 + name.length + pack.length);
  final header = ByteData.sublistView(bytes);
  header.setUint32(0, 0x04034b50, Endian.little);
  header.setUint16(6, 0x800, Endian.little);
  header.setUint32(14, filmCrc(pack), Endian.little);
  header.setUint32(18, pack.length, Endian.little);
  header.setUint32(22, pack.length, Endian.little);
  header.setUint16(26, name.length, Endian.little);
  bytes.setRange(30, 30 + name.length, name);
  bytes.setRange(30 + name.length, bytes.length, pack);
  return bytes;
}

void main() {
  test(
      'Leica sync binds phone preview to the SD record and preserves old cache',
      () async {
    final dir = Directory.systemTemp.createTempSync('leica-official-');
    addTearDown(() => dir.deleteSync(recursive: true));
    var stocks = [
      {'id': 331, 'native_values': List.filled(10125, 153)}
    ];
    final library = OfficialFilmLibrary(
        directory: () async => dir,
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/api/gr3/native-library/catalog':
              return http.Response.bytes(
                  utf8.encode('{"film_count":1,"films":[{"id":331,'
                      '"name":"Leica Chrome","group":"影像",'
                      '"icon_url":"/gr3/film-icons/331.png"}]}'),
                  200);
            case '/api/status':
              return http.Response('{"session_token":"fixture"}', 200);
            case '/api/gr3/sd-library/export':
              expect(jsonDecode(request.body)['ids'], [331]);
              return http.Response.bytes(
                  storedZip(samplePack(filmId: 331)), 200);
            case '/gr3/leica-luts.json':
              return http.Response(
                  jsonEncode({
                    'size': 15,
                    'bits': 8,
                    'order': 'RGB, blue fastest',
                    'stocks': stocks,
                  }),
                  200);
          }
          throw StateError('unexpected ${request.url.path}');
        }));

    final result = await library.sync(expectedRenderer: 'bb' * 32);
    expect(result.films.single.group, '影像');
    expect(result.phoneLuts.single.id, startsWith('official:331:default:'));
    expect(result.cameraCompatible, isFalse);
    final cache = File('${dir.path}/official-library.json');
    final before = cache.readAsStringSync();
    for (final bad in [
      <Map<String, Object>>[],
      [
        {'id': 331, 'native_values': List.filled(10125, 154)}
      ],
    ]) {
      stocks = bad;
      await expectLater(
          library.sync(expectedRenderer: 'bb' * 32), throwsFormatException);
      expect(cache.readAsStringSync(), before);
    }
  });

  test(
      'sync activates immutable phone color data independently of camera version',
      () async {
    final dir = Directory.systemTemp.createTempSync('phone-official-');
    addTearDown(() => dir.deleteSync(recursive: true));
    var failColor = false;
    var colorByte = 153;
    final library = OfficialFilmLibrary(
        directory: () async => dir,
        client: MockClient((request) async {
          if (request.url.path == '/api/gr3/native-library/catalog') {
            return http.Response(
                jsonEncode({
                  'film_count': 1,
                  'films': [
                    {
                      'id': 326,
                      'name': 'Vista 200',
                      'group': 'C41',
                      'icon_url': '/gr3/film-icons/326.png'
                    }
                  ]
                }),
                200);
          }
          if (request.url.path == '/api/status') {
            return http.Response('{"session_token":"fixture"}', 200);
          }
          if (request.url.path == '/api/gr3/sd-library/export') {
            return http.Response.bytes(storedZip(samplePack(filmId: 326)), 200);
          }
          if (request.url.path == '/gr3/c41-luts.json') {
            return failColor
                ? http.Response('offline', 503)
                : http.Response(
                    jsonEncode({
                      'size': 15,
                      'bits': 8,
                      'order': 'RGB, blue fastest',
                      'stocks': [
                        {
                          'id': 326,
                          'values': List.filled(10125, 0),
                          'native_values': List.filled(10125, colorByte)
                        }
                      ]
                    }),
                    200);
          }
          throw StateError('unexpected ${request.url.path}');
        }));
    final result = await library.sync(expectedRenderer: 'bb' * 32);
    final raw = jsonDecode(
        await File('${dir.path}/official-library.json').readAsString()) as Map;
    expect(raw['phoneLuts'], hasLength(1));
    final record = (raw['phoneLuts'] as List).single as Map;
    expect(record['filmId'], 326);
    expect(record['id'], startsWith('official:326:default:'));
    expect(
        File('${dir.path}/official-luts/${record['contentHash']}.cube')
            .readAsStringSync(),
        contains('0.60000000'));
    expect(result.cameraCompatible, isFalse);
    final before =
        await File('${dir.path}/official-library.json').readAsString();
    colorByte = 154;
    await expectLater(
        library.sync(expectedRenderer: 'bb' * 32), throwsFormatException);
    expect(
        await File('${dir.path}/official-library.json').readAsString(), before);
    colorByte = 153;
    failColor = true;
    await expectLater(library.sync(expectedRenderer: 'bb' * 32),
        throwsA(isA<HttpException>()));
    expect(
        await File('${dir.path}/official-library.json').readAsString(), before);
    expect((await library.cached(expectedRenderer: 'bb' * 32))?.sha256,
        result.sha256);
  });
  test('new website IDs remain browsable without becoming camera recipes', () {
    final films = parseOfficialCatalog(jsonEncode({
      'film_count': 1,
      'films': [
        {
          'id': 326,
          'name': 'Agfa Vista 200',
          'group': 'C41',
          'icon_url': '/gr3/film-icons/326.png'
        }
      ]
    }));
    expect(films.single.id, 326);
    for (final id in [0, -1, 0x100000000]) {
      expect(
          () => OfficialFilm.parse({
                'id': id,
                'name': 'invalid',
                'group': 'C41',
                'icon_url': '/gr3/a.png'
              }),
          throwsFormatException);
    }
  });
  test(
      'new official renderer can sync for browsing without replacing camera recipes',
      () async {
    final dir = Directory.systemTemp.createTempSync('official-films-');
    addTearDown(() => dir.deleteSync(recursive: true));
    var corrupt = false;
    final library = OfficialFilmLibrary(
      directory: () async => dir,
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/gr3/native-library/catalog':
            return http.Response(
                jsonEncode({
                  'film_count': 1,
                  'films': [
                    {
                      'id': 33,
                      'name': '800T',
                      'group': 'ECN2',
                      'icon_url': '/gr3/film-icons/33.png'
                    }
                  ]
                }),
                200);
          case '/api/status':
            return http.Response('{"session_token":"fixture"}', 200);
          case '/api/gr3/sd-library/export':
            expect(request.method, 'POST');
            expect(jsonDecode(request.body)['ids'], [33]);
            final pack = samplePack();
            if (corrupt) pack[4096 + 64] ^= 1;
            return http.Response.bytes(storedZip(pack), 200);
          default:
            throw StateError('Unexpected target');
        }
      }),
    );
    // Production regression: rejecting a valid newer renderer hides the entire
    // website catalogue. Browsing must work; camera compatibility stays explicit.
    final snapshot = await library.sync(expectedRenderer: 'bb' * 32);
    expect(snapshot.films.single.name, '800T');
    expect(snapshot.rendererHash, 'aa' * 32);
    expect(snapshot.cameraCompatible, isFalse);
    final cached = await library.cached(expectedRenderer: 'bb' * 32);
    expect(cached?.films.single.id, 33);
    expect(cached?.cameraCompatible, isFalse);
    expect(
        (await library.cached(expectedRenderer: 'aa' * 32))?.cameraCompatible,
        isTrue);
    expect((await library.cached())?.cameraCompatible, isFalse);
    corrupt = true;
    await expectLater(
        library.sync(expectedRenderer: 'bb' * 32), throwsFormatException);
    expect((await library.cached(expectedRenderer: 'bb' * 32))?.sha256,
        snapshot.sha256);
  });
  test('valid SD records must match the pinned renderer on every record', () {
    final bytes = samplePack();
    expect(() => validateOfficialPack(bytes, {33}, expectedRenderer: 'aa' * 32),
        returnsNormally);
    expect(() => validateOfficialPack(bytes, {33}, expectedRenderer: 'bb' * 32),
        throwsFormatException);
    bytes[4096 + 64] ^= 1;
    expect(() => validateOfficialPack(bytes, {33}, expectedRenderer: 'aa' * 32),
        throwsFormatException);
  });

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
