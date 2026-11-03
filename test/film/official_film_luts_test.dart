import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/film/catalog/official_film_library.dart';
import 'package:gremote/film/catalog/official_film_luts.dart';

OfficialFilm film(int id) =>
    OfficialFilm(id: id, name: 'Film $id', group: 'Test', icon: '/gr3/$id.png');
List<int> table(int value) => List<int>.filled(15 * 15 * 15 * 3, value);
Map<String, dynamic> source(List<Map<String, dynamic>> stocks) =>
    {'size': 15, 'bits': 8, 'order': 'RGB, blue fastest', 'stocks': stocks};
List<List<double>> rows(OfficialColorLut lut) => utf8
    .decode(lut.cube)
    .split('\n')
    .where((s) => RegExp(r'^\d').hasMatch(s))
    .map((s) => s.split(' ').map(double.parse).toList())
    .toList();

void main() {
  test('transposes asymmetric blue-fastest source into red-fastest cube', () {
    final values = table(0);
    values.setRange(3, 6, [17, 34, 51]); // source blue=1
    values
        .setRange(15 * 15 * 3, 15 * 15 * 3 + 3, [68, 85, 102]); // source red=1
    final lut = compileOfficialFilmLuts(films: [
      film(69)
    ], sources: {
      '/gr3/curated-luts.json': source([
        {'id': 69, 'values': values}
      ])
    }).single;
    expect(lut.size, 15);
    expect(rows(lut)[1][0], closeTo(68 / 255, 0.000001));
    expect(rows(lut)[225][0], closeTo(17 / 255, 0.000001));
    expect(lut.variant, 'default');
    expect(lut.approximationLabel, contains('近似'));
  });
  test(
      'uses native preview values for newer native profiles, never target values',
      () {
    final lut = compileOfficialFilmLuts(films: [
      film(326)
    ], sources: {
      '/gr3/c41-luts.json': source([
        {'id': 326, 'values': table(0), 'native_values': table(255)}
      ])
    }).single;
    expect(rows(lut).first, [1, 1, 1]);
    expect(
        () => compileOfficialFilmLuts(films: [
              film(326)
            ], sources: {
              '/gr3/c41-luts.json': source([
                {'id': 326, 'values': table(0)}
              ])
            }),
        throwsFormatException);
  });
  test('preserves distinct Harman EI variants without rebinding identities',
      () {
    final luts = compileOfficialFilmLuts(films: [
      film(67),
      film(68)
    ], sources: {
      '/gr3/harman-luts.json': source([
        {'id': 68, 'ei': 250, 'values': table(250)},
        {'id': 67, 'ei': 120, 'values': table(120)},
        {'id': 68, 'ei': 125, 'values': table(125)},
        {'id': 67, 'ei': 200, 'values': table(200)},
        {'id': 68, 'ei': 64, 'values': table(64)}
      ])
    });
    expect(luts.map((l) => '${l.filmId}/${l.variant}'),
        ['67/default', '67/ei120', '68/default', '68/ei64', '68/ei250']);
    expect(luts.map((l) => l.id).toSet().length, 5);
  });
  test(
      'rejects malformed table numbers, geometry and duplicate supported identity',
      () {
    for (final bad in [-1, 256, 0.5, double.nan, double.infinity, '1']) {
      final values = <dynamic>[...table(0)]..[0] = bad;
      expect(
          () => compileOfficialFilmLuts(films: [
                film(69)
              ], sources: {
                '/gr3/curated-luts.json': source([
                  {'id': 69, 'values': values}
                ])
              }),
          throwsFormatException);
    }
    for (final change in [
      {'size': 16},
      {'bits': 16},
      {'order': 'RGB, red fastest'}
    ]) {
      expect(
          () => compileOfficialFilmLuts(films: [
                film(69)
              ], sources: {
                '/gr3/curated-luts.json': source([
                  {'id': 69, 'values': table(0)}
                ])
                  ..addAll(change)
              }),
          throwsFormatException);
    }
    for (final stocks in [
      [
        {
          'id': 69,
          'values': [0]
        }
      ],
      [
        {'id': 69, 'values': table(0)},
        {'id': 69, 'values': table(0)}
      ]
    ]) {
      expect(
          () => compileOfficialFilmLuts(
              films: [film(69)],
              sources: {'/gr3/curated-luts.json': source(stocks)}),
          throwsFormatException);
    }
    expect(
        () => compileOfficialFilmLuts(films: [film(69), film(69)], sources: {}),
        throwsFormatException);
  });
  test(
      'content addressed immutable cube remains deterministic after source mutation',
      () {
    final values = table(0),
        stocks = [
          {'id': 69, 'values': values}
        ];
    final inputs = {'/gr3/curated-luts.json': source(stocks)};
    final a =
        compileOfficialFilmLuts(films: [film(69)], sources: inputs).single;
    final b =
        compileOfficialFilmLuts(films: [film(69)], sources: inputs).single;
    expect(a.id, b.id);
    expect(a.id, startsWith('official:69:default:'));
    expect(a.contentHash.length, 64);
    values[0] = 255;
    expect(rows(a).first, [0, 0, 0]);
    expect(() => a.cube[0] = 0, throwsUnsupportedError);
    expect(
        compileOfficialFilmLuts(films: [film(69)], sources: inputs).single.id,
        isNot(a.id));
  });
  test('missing special and future formats stay explicitly unavailable', () {
    expect(
        compileOfficialFilmLuts(
            films: [film(33), film(289), film(290), film(999)], sources: {}),
        isEmpty);
    expect(
        compileOfficialFilmLuts(films: [
          film(999)
        ], sources: {
          '/gr3/c41-luts.json': source([
            {'id': 999, 'futureFormat': true}
          ])
        }),
        isEmpty);
  });
  test('compiles 5207 and legacy matrix curves with positional historical IDs',
      () {
    final curve = List.generate(256, (i) => (i * 16383 / 255).round());
    final looks = List.generate(
        32,
        (i) => {
              'matrixQ13': [8192, 0, 0, 0, 8192, 0, 0, 0, 8192],
              'postQ512': [0, 512, 0, 512, 0, 0, 0, 0, 512],
              'curves': [curve, curve, curve]
            });
    final luts = compileOfficialFilmLuts(films: [
      film(34),
      film(65),
      film(66)
    ], sources: {
      '/gr3/film-catalog.json': {'looks': looks},
      '/gr3/5207-lut.json': {
        'size': 15,
        'bits': 8,
        'order': 'RGB, blue fastest',
        'values': table(127)
      }
    });
    expect(luts.map((l) => l.filmId), [34, 65, 66]);
    expect(luts.first.size, 33);
    final red = rows(luts.first)[32];
    expect(red, [0, 1, 0]);
    expect(rows(luts.last).first[0], closeTo(127 / 255, 0.000001));
    expect(
        () => compileOfficialFilmLuts(films: [
              film(34)
            ], sources: {
              '/gr3/film-catalog.json': {'looks': []}
            }),
        throwsFormatException);
  });
  test('bounds source count, stock count and decoded numeric payload bytes',
      () {
    expect(
        () => compileOfficialFilmLuts(
            films: [film(69)],
            sources: {for (var i = 0; i < 13; i++) '/unknown/$i': {}}),
        throwsFormatException);
    expect(
        () => compileOfficialFilmLuts(films: [
              film(69)
            ], sources: {
              '/gr3/curated-luts.json':
                  source(List.generate(257, (i) => {'id': 1000 + i}))
            }),
        throwsFormatException);
    expect(
        () => compileOfficialFilmLuts(films: [
              film(69)
            ], sources: {
              '/gr3/curated-luts.json': {
                'padding': 'x' * (16 * 1024 * 1024 + 1)
              }
            }),
        throwsFormatException);
  });
}
