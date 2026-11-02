import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/darkroom/model/export_recipe.dart';
import 'package:gremote/darkroom/model/photo_edits.dart';

void main() {
  test('old recipe restores a neutral editable original', () {
    final recipe = ExportRecipe.fromJson({'frame': 'none'});
    expect(recipe.edits, const PhotoEdits());
    expect(recipe.edits.crop.outputSize(6000, 4000), (6000, 4000));
    final p = recipe.edits.nativeParameters;
    expect(p.length, 1062);
    expect(p[0], 1);
    expect(p[1], 0);
    expect(p[29], 7331);
    expect(p.sublist(30, 38), [0, 0, 1, 1, 0, 0, 0, 0]);
    for (var channel = 0; channel < 4; channel++) {
      expect(p[38 + channel * 256], 0);
      expect(p[38 + channel * 256 + 255], 1);
    }
  });

  test('all edits survive save and cannot retain invalid numeric values', () {
    var e = const PhotoEdits();
    for (final a in PhotoAdjustment.values) {
      e = e.withValue(a, (a.min + a.max) / 3);
    }
    e = e.copyWith(
      crop: const CropEdit(
          left: .1,
          top: .2,
          width: .6,
          height: .5,
          quarterTurns: 1,
          flipX: true,
          angle: 8),
      seed: 741,
      curves: [
        ToneCurve.fromPoints([
          const CurvePoint(0, .1),
          const CurvePoint(.5, .7),
          const CurvePoint(1, .95)
        ]),
        const ToneCurve(),
        const ToneCurve(),
        const ToneCurve()
      ],
    );
    final r = const ExportRecipe().copyWith(edits: e);
    expect(ExportRecipe.fromJson(r.toJson()), r);
    expect(
        e
            .withValue(PhotoAdjustment.exposure, double.nan)
            .value(PhotoAdjustment.exposure),
        0);
    expect(
        e
            .withValue(PhotoAdjustment.exposure, 99)
            .value(PhotoAdjustment.exposure),
        3);
    final restored = PhotoEdits.fromJson({
      'values': {'grain': 'bad'},
      'seed': -200,
      'crop': {'left': 2, 'top': -1, 'width': 0, 'height': 9}
    });
    expect(restored.value(PhotoAdjustment.grain), 0);
    expect(restored.crop.outputSize(6, 4).$1, greaterThanOrEqualTo(1));
    expect(restored.nativeParameters.every((v) => v.isFinite), isTrue);
  });

  test('crop swaps axes once and never exports zero pixels', () {
    expect(
        const CropEdit(quarterTurns: 1, width: .5, height: .5)
            .outputSize(6000, 4000),
        (2000, 3000));
    expect(const CropEdit(width: .000001, height: .000001).outputSize(2, 1),
        (1, 1));
    expect(
        CropEdit.fromJson({'quarterTurns': 9, 'angle': 100}).quarterTurns, 1);
    expect(CropEdit.fromJson({'angle': 100}).angle, 45);
  });

  test('curves sort merge duplicates and preserve smooth bounded tones', () {
    final c = ToneCurve.fromPoints([
      const CurvePoint(1, 1),
      const CurvePoint(.5, .8),
      const CurvePoint(.5, .6),
      const CurvePoint(0, 0),
      CurvePoint(double.nan, .9)
    ]);
    expect(c.points.length, 3);
    expect(c.points[1].y, .6);
    final samples = c.samples();
    expect(samples.length, 256);
    expect(samples.first, 0);
    expect(samples.last, 1);
    for (var i = 1; i < samples.length; i++) {
      expect(samples[i], greaterThanOrEqualTo(samples[i - 1]));
      expect(samples[i], inInclusiveRange(0, 1));
    }
    expect(samples[128], closeTo(.6, .01));
    expect(ToneCurve.fromJson(c.toJson()), c);
  });
}
