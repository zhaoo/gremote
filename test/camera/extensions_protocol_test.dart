import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/extensions_protocol.dart';

void main() {
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
