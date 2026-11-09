import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/extensions_protocol.dart';
import 'extensions_controller_test.dart' show extCaps, extSnapshot;

void main() {
  test('previous camera contract remains readable and cannot write vignette',
      () {
    final caps = extCaps()..['contractHash'] = previousExtensionContractHash;
    caps['fields'] = (caps['fields'] as List)
        .where((f) => !(f['key'] as String).startsWith('vignette'))
        .toList();
    expect(ExtensionCapabilities.fromJson(caps).supported, contains('hdf'));
    expect(
        extensionValueSupported(
            previousExtensionContractHash, 'vignetteEnabled', 1),
        isFalse);
    expect(
        extensionValueSupported(extensionContractHash, 'vignetteStrength', 0),
        isFalse);
    expect(
        extensionValueSupported(extensionContractHash, 'vignetteStrength', 3),
        isTrue);
  });
  test('legacy extensions remain readable without exposing imprint', () {
    final caps = extCaps()..['contractHash'] = legacyExtensionContractHash;
    for (final field in caps['fields'] as List) {
      if (field['key'] == 'leakPosition') field['max'] = 2;
    }
    caps['fields'] = (caps['fields'] as List)
        .where((field) =>
            field['key'] != 'imprint' &&
            !(field['key'] as String).startsWith('vignette'))
        .toList();
    final legacy = ExtensionCapabilities.fromJson(caps);
    expect(legacy.supported, contains('hdf'));
    expect(legacy.supported, isNot(contains('imprint')));
    final state = extSnapshot()..['contractHash'] = legacyExtensionContractHash;
    expect(ExtensionSnapshot.fromJson(state).values['hdf'], 0);
    state['supported'] = ['imprint'];
    state['values'] = {'imprint': 1};
    expect(() => ExtensionSnapshot.fromJson(state), throwsFormatException);
  });

  test('imprint exposes seven named styles and rejects out of range values',
      () {
    final field = extensionFields['imprint'];
    expect(field, isNotNull);
    expect(field!.label, '胶卷印花');
    expect(field.accepts(7), isTrue);
    expect(field.accepts(8), isFalse);
    expect(field.choices![0], '关闭');
    expect(field.choices![7], '宝可梦');
  });

  test('extension fields preserve raw aspect IDs and explicit ranges', () {
    expect(extensionFields['aspect']!.choices![6], 'Half 3:4');
    expect(extensionFields['aspect']!.choices![3], '1:1');
    expect(extensionFields['focalA']!.accepts(27), isFalse);
    expect(extensionFields['focalA']!.accepts(50), isTrue);
    expect(extensionFields['hdf']!.accepts(4), isFalse);
  });
  test('invalid values and unknown extension keys fail closed', () {
    final snapshot = {
      'schema': extensionSchema,
      'contractHash': extensionContractHash,
      'instanceId': '01' * 16,
      'buildId': '02' * 32,
      'bootId': '03' * 16,
      'revision': '04' * 32,
      'busy': false,
      'supported': ['hdf'],
      'values': {'hdf': 8}
    };
    expect(() => ExtensionSnapshot.fromJson(snapshot), throwsFormatException);
    snapshot['values'] = {'hdf': 1, 'unknown': 1};
    expect(() => ExtensionSnapshot.fromJson(snapshot), throwsFormatException);
  });
}
