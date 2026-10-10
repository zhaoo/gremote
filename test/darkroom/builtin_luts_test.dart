import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/darkroom/lut/builtin_looks.dart';
import 'package:gremote/darkroom/lut/cube_writer.dart';

List<List<double>> rows(String cube) => cube
    .split('\n')
    .where((line) => line.isNotEmpty && RegExp(r'^[0-9]').hasMatch(line))
    .map((line) => line.split(' ').map(double.parse).toList())
    .toList();

void main() {
  test('ships five original looks with stable ids', () {
    expect(builtinLooks.map((look) => look.id), [
      'builtin:warm-positive',
      'builtin:cool-negative',
      'builtin:hard-mono',
      'builtin:pale',
      'builtin:night-teal-gold',
    ]);
  });

  for (final look in builtinLooks) {
    test('${look.slug} asset matches the generator byte for byte', () {
      final asset = File(look.assetPath);
      expect(asset.existsSync(), isTrue,
          reason: 'run: dart run tool/generate_luts.dart');
      expect(asset.readAsStringSync(), look.toCube());
    });

    test('${look.slug} is a 33 point LUT within [0, 1]', () {
      final cube = look.toCube();
      expect(cube, contains('LUT_3D_SIZE 33\n'));
      final values = rows(cube);
      expect(values, hasLength(33 * 33 * 33));
      for (final row in values) {
        expect(row, hasLength(3));
        for (final v in row) {
          expect(v, inInclusiveRange(0, 1));
        }
      }
    });
  }

  test('hard-mono is neutral', () {
    final look = builtinLooks.firstWhere((l) => l.slug == 'hard-mono');
    for (final row in rows(look.toCube())) {
      expect(row[0], row[1]);
      expect(row[1], row[2]);
    }
  });

  test('identity mapping writes an identity cube', () {
    final cube = writeCube(title: 'id', size: 3, map: (r, g, b) => [r, g, b]);
    final values = rows(cube);
    expect(values.first, [0, 0, 0]);
    expect(values[1], [0.5, 0, 0]);
    expect(values[3], [0, 0.5, 0]);
    expect(values.last, [1, 1, 1]);
    expect(cube, isNot(contains('-0.000000')));
  });
}
