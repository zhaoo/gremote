import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/params/exposure_values.dart';

void main() {
  test('shutter strings parse to seconds', () {
    expect(parseTvSeconds('1/250'), closeTo(0.004, 1e-9));
    expect(parseTvSeconds('2'), 2);
    expect(parseTvSeconds('2.5"'), 2.5);
    expect(parseTvSeconds('30s'), 30);
    expect(parseTvSeconds('bulb'), isNull);
    expect(parseTvSeconds('1/0'), isNull);
  });

  test('ISO and EV strings parse', () {
    expect(parseIso('400'), 400);
    expect(parseIso('auto'), isNull);
    expect(parseEv('+0.3'), closeTo(0.3, 1e-9));
    expect(parseEv('-1/3'), closeTo(-1 / 3, 1e-9));
    expect(parseEv('0'), 0);
    expect(parseEv('x'), isNull);
  });

  test('nearestByLog picks the closest stop and honours max', () {
    const tvs = ['1/1000', '1/250', '1/60', '1/15', '1/4', '1', '4'];
    expect(nearestByLog(tvs, log2(1 / 200), parseTvSeconds), '1/250');
    expect(nearestByLog(tvs, log2(3), parseTvSeconds), '4');
    expect(nearestByLog(tvs, log2(3), parseTvSeconds, max: 2), '1');
    expect(nearestByLog(const ['auto'], 1, parseIso), isNull);
  });

  test('allParse reports unknown formats', () {
    expect(allParse(['100', 'auto'], parseIso, allow: {'auto'}), isTrue);
    expect(allParse(['100', 'L1'], parseIso), isFalse);
    expect(allParse([], parseIso), isFalse);
  });
}
