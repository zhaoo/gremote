import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gremote/film/catalog/official_film_library.dart';

Uint8List samplePack() {
  final bytes = Uint8List(4096 + 12288), header = ByteData.sublistView(bytes);
  bytes.setRange(0, 8, ascii.encode('M10VSD1\x00'));
  for (final e in {
    8: 1,
    12: bytes.length,
    16: 1,
    20: 12288,
    24: 239,
    28: 1,
    64: 33,
    72: 1
  }.entries) {
    header.setUint32(e.key, e.value, Endian.little);
  }
  final record = Uint8List.sublistView(bytes, 4096),
      data = ByteData.sublistView(record);
  record.setRange(0, 8, ascii.encode('M10VREC1'));
  data.setUint32(8, 33, Endian.little);
  record.fillRange(8448, 8480, 0xaa);
  final crc = filmCrc(record.sublist(0, 12284));
  data.setUint32(12284, crc, Endian.little);
  header.setUint32(68, crc, Endian.little);
  header.setUint32(4092, filmCrc(bytes.sublist(0, 4092)), Endian.little);
  return bytes;
}

void main() {
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
