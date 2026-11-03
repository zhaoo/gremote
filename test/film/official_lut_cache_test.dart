import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/film/catalog/official_film_luts.dart';
import 'package:gremote/film/catalog/official_lut_cache.dart';

import 'official_film_luts_test.dart' show film, source, table;

OfficialColorLut colorLut(int id, int value) => compileOfficialFilmLuts(films: [
      film(id)
    ], sources: {
      '/gr3/curated-luts.json': source([
        {'id': id, 'values': table(value)}
      ])
    }).single;

void main() {
  late Directory dir;
  late OfficialLutCache cache;
  late File manifest;
  Future<void> activate(List<Map<String, Object?>> entries) =>
      manifest.writeAsString(jsonEncode({'phoneLuts': entries})).then((_) {});

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('official-lut-cache');
    cache = OfficialLutCache(directory: () async => dir);
    manifest = File('${dir.path}/official-library.json');
  });
  tearDown(() => dir.delete(recursive: true));

  test('staging verifies every payload without activating a manifest',
      () async {
    final lut = colorLut(69, 20);
    final descriptors = await cache.stage([lut]);
    expect(await manifest.exists(), isFalse);
    expect(await cache.entries(), isEmpty);
    expect(await cache.load(lut.id), orderedEquals(lut.cube));
    await activate(descriptors);
    final record = (await cache.entries()).single;
    expect(record.id, lut.id);
    expect(record.name, 'Film 69');
    expect(record.filmId, 69);
    expect(record.size, 15);
    expect(record.contentHash, lut.contentHash);
    expect(record.byteLength, lut.cube.length);
  });

  test(
      'an interrupted stage leaves the prior active cache byte-for-byte intact',
      () async {
    final old = colorLut(69, 0),
        first = colorLut(69, 100),
        last = colorLut(70, 200);
    await activate(await cache.stage([old]));
    final before = await manifest.readAsBytes();
    // A directory at the next immutable payload path simulates a disk failure.
    await Directory('${dir.path}/official-luts/${last.contentHash}.cube')
        .create();
    await expectLater(cache.stage([first, last]), throwsA(anything));
    expect(await manifest.readAsBytes(), orderedEquals(before));
    expect((await cache.entries()).single.id, old.id);
    expect(await cache.load(old.id), orderedEquals(old.cube));
    expect(await cache.load(first.id), orderedEquals(first.cube));
  });

  test('updated active metadata never rebinds historical saved-edit IDs',
      () async {
    final old = colorLut(69, 0), updated = colorLut(69, 255);
    await activate(await cache.stage([old]));
    await activate(await cache.stage([updated]));
    expect((await cache.entries()).single.id, updated.id);
    expect(old.id, isNot(updated.id));
    expect(await cache.load(old.id), orderedEquals(old.cube));
    expect(await cache.load(updated.id), orderedEquals(updated.cube));
    await manifest.delete();
    expect(await cache.load(old.id), orderedEquals(old.cube));
  });

  test('old cache without phone LUTs is empty', () async {
    await manifest.writeAsString(jsonEncode({'catalog': 'old', 'pack': 'old'}));
    expect(await cache.entries(), isEmpty);
    expect(await cache.load('builtin:pale'), isNull);
  });

  test('record validation rejects inconsistent identity, paths and size limits',
      () async {
    final descriptor = (await cache.stage([colorLut(69, 0)])).single;
    for (final mutation in <Map<String, Object?>>[
      {'id': 'official:69:default:../../outside'},
      {'id': '${descriptor['id']}\n'},
      {'id': descriptor['id'].toString().replaceFirst(':69:', ':70:')},
      {'contentHash': 'a' * 64},
      {'filmId': -1},
      {'variant': '../default'},
      {'size': 128},
      {'name': 'x' * 81},
      {'name': ''},
      {'byteLength': 0},
      {'byteLength': 2 * 1024 * 1024 + 1},
      {'filePath': '/tmp/outside.cube'},
    ]) {
      expect(() => OfficialLutRecord.fromJson({...descriptor, ...mutation}),
          throwsFormatException,
          reason: '$mutation');
      await activate([
        {...descriptor, ...mutation}
      ]);
      expect(await cache.entries(), isEmpty, reason: '$mutation');
    }
  });

  test('missing, corrupt, oversized and symlink payloads fail closed',
      () async {
    final lut = colorLut(69, 0),
        descriptors = await cache.stage([colorLut(69, 0)]);
    final payload = File('${dir.path}/official-luts/${lut.contentHash}.cube');
    await activate(descriptors);
    // Same length corruption passes cheap metadata checks but fails load SHA.
    final corrupt = Uint8List.fromList(lut.cube)..[0] ^= 1;
    await payload.writeAsBytes(corrupt);
    expect((await cache.entries()).single.id, lut.id);
    expect(await cache.load(lut.id), isNull);
    await expectLater(cache.stage([lut]), throwsFormatException);
    await payload.writeAsBytes(Uint8List(2 * 1024 * 1024 + 1));
    expect(await cache.entries(), isEmpty);
    expect(await cache.load(lut.id), isNull);
    await payload.delete();
    expect(await cache.entries(), isEmpty);
    expect(await cache.load(lut.id), isNull);
    final outside =
        await File('${dir.path}/outside.cube').writeAsBytes(lut.cube);
    await Link(payload.path).create(outside.path);
    expect(await cache.entries(), isEmpty);
    expect(await cache.load(lut.id), isNull);
    for (final id in [
      'official:69:default:../outside',
      '${lut.id}/../outside',
      'official:0:default:${lut.contentHash}',
      'official:69:unknown:${lut.contentHash}',
      'official:69:default:${lut.contentHash.toUpperCase()}'
    ]) {
      expect(await cache.load(id), isNull);
    }
  });

  test('bounds entry count, duplicate identities, aggregate and manifest bytes',
      () async {
    final lut = colorLut(69, 0),
        descriptor = (await cache.stage([colorLut(69, 0)])).single;
    await expectLater(cache.stage(List.filled(81, lut)), throwsFormatException);
    await expectLater(cache.stage([lut, lut]), throwsFormatException);
    await activate(List.filled(81, descriptor));
    expect(await cache.entries(), isEmpty);
    await activate([descriptor, descriptor]);
    expect(await cache.entries(), isEmpty);
    await activate([
      for (var id = 1; id <= 33; id++)
        {
          ...descriptor,
          'id': 'official:$id:default:${lut.contentHash}',
          'filmId': id,
          'byteLength': 2 * 1024 * 1024,
        }
    ]);
    expect(await cache.entries(), isEmpty);
    await manifest.writeAsBytes(Uint8List(6 * 1024 * 1024 + 1));
    expect(await cache.entries(), isEmpty);
  });
}
