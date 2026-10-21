import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/three_way_merge.dart';
import 'package:gremote/camera/companion/companion_protocol.dart';
import 'companion_client_test.dart' show capabilities;

Map<String, Object?> config() => {
      'slots': List.generate(
          5,
          (_) => <String, Object?>{
                'filmId': 33,
                'parameters': <String, Object?>{'grain': 0, 'grainSize': 1},
                'customHash': null
              }),
      'globals': <String, Object?>{
        'stamp': 0,
        'format': 0,
        'corner': 0,
        'color': 0,
        'filmNameStamp': 0
      }
    };
Map<String, Object?> clone(Map<String, Object?> value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
void grain(Map<String, Object?> config, int value) =>
    (((config['slots'] as List)[0] as Map)['parameters'] as Map)['grain'] =
        value;
void main() {
  final caps = CompanionCapabilities.fromJson(capabilities());
  test('fieldwise changes on one side merge; equal changes do not conflict',
      () {
    final b = config(), l = clone(config()), r = clone(config());
    grain(l, 2);
    ((r['slots'] as List)[1]['parameters'] as Map)['grain'] = 1;
    final merged =
        threeWayMerge(base: b, local: l, remote: r, capabilities: caps);
    expect(merged.conflicts, isEmpty);
    expect((merged.merged['slots'] as List)[0]['parameters']['grain'], 2);
    expect((merged.merged['slots'] as List)[1]['parameters']['grain'], 1);
    grain(r, 2);
    expect(
        threeWayMerge(base: b, local: l, remote: r, capabilities: caps)
            .conflicts,
        isEmpty);
  });
  test(
      'same-field conflict requires explicit choice; keep both retains remote slot',
      () {
    final b = config(), l = clone(b), r = clone(b);
    grain(l, 1);
    grain(r, 2);
    ((l['slots'] as List)[0]['parameters'] as Map)['grainSize']=2;
    final merged =
        threeWayMerge(base: b, local: l, remote: r, capabilities: caps);
    expect(merged.conflicts.single.path, 'slots.0.parameters.grain');
    expect(merged.resolved, isFalse);
    final selected =
        merged.resolve({'slots.0.parameters.grain': ConflictChoice.keepBoth});
    expect(selected.resolved, isTrue);
    expect((selected.merged['slots'] as List)[0]['parameters']['grain'], 2);
    expect(selected.keepLocalSlots, {0});
    expect((selected.merged['slots'] as List)[0]['parameters']['grainSize'],1);
  });
  test('unknown fields are preserved and forbid old-model writes', () {
    final b = config(), l = clone(b), r = clone(b);
    r['future'] = {'setting': 7};
    grain(l, 2);
    final merged =
        threeWayMerge(base: b, local: l, remote: r, capabilities: caps);
    expect(merged.readOnly, isTrue);
    expect(merged.merged['future'], {'setting': 7});
    expect(r['future'], {'setting': 7});
  });
}
