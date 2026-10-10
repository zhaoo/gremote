import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/params/camera_param.dart';
import 'package:gremote/camera/protocol/props_parser.dart';
import 'package:gremote/camera/sync/camera_state.dart';

Map<String, Object?> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, Object?>;

void main() {
  final derived = CameraState.offline
      .applyProps(parseProps(_fixture('props_gr3_derived.json')));

  test('known parameters parse with their camera lists', () {
    expect(derived.value(ParamKey.aperture), '2.8');
    expect(derived.param(ParamKey.aperture)!.options, hasLength(7));
    expect(derived.value(ParamKey.shutter), '1/250');
    expect(derived.value(ParamKey.effect), 'standard');
    expect(derived.param(ParamKey.drive)!.options, contains('interval'));
    expect(derived.param(ParamKey.focusSetting)!.endpoint, ParamEndpoint.lens);
  });

  test('writability follows the list and the physical dial', () {
    expect(derived.param(ParamKey.aperture)!.writable, isTrue);
    expect(derived.param(ParamKey.shutter)!.writable, isFalse);
    expect(derived.param(ParamKey.exposureMode)!.writable, isFalse);
  });

  test('x + xList pairs become extras; lone values do not', () {
    final extras = derived.extras.map((p) => p.wireKey).toList();
    expect(extras, ['noiseReduction']);
    expect(derived.params.containsKey('orphanValue'), isFalse);
  });

  test('status fields are read and never become parameters', () {
    expect(derived.status.remain, 812);
    expect(derived.status.battery, 82);
    expect(derived.status.hot, isFalse);
    expect(derived.params.containsKey('storages'), isFalse);
    expect(derived.keyTypes['storages'], 'list');
    expect(derived.keyTypes['ssid'], 'string');
  });

  test('a partial update keeps the previous option list', () {
    final next = derived.applyProps(parseProps({'av': '4.0', 'remain': 3}));
    expect(next.value(ParamKey.aperture), '4.0');
    expect(next.param(ParamKey.aperture)!.options, hasLength(7));
    expect(next.status.remain, 812);
  });

  test('battery may be an object and odd types are ignored', () {
    final parsed = parseProps({
      'battery': {'level': 40},
      'av': {'nested': true},
      'tvList': 'not-a-list',
      'storages': 'none',
    });
    expect(parsed.status.battery, 40);
    expect(parsed.params, isEmpty);
    expect(parsed.status.remain, isNull);
  });

  test('the legacy props fixture parses without throwing', () {
    final state =
        CameraState.offline.applyProps(parseProps(_fixture('props.json')));
    expect(state.params.containsKey('model'), isFalse);
    expect(state.keyTypes['futureCapability'], 'object');
  });
}
