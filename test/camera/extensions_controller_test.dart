import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/extensions_protocol.dart';
import 'package:gremote/camera/companion/extensions_controller.dart';

Map<String, dynamic> extSnapshot({int hdf = 0, String revision = '04'}) => {
      'schema': extensionSchema,
      'contractHash': extensionContractHash,
      'instanceId': '01' * 16,
      'buildId': '02' * 32,
      'bootId': '03' * 16,
      'revision': revision * 32,
      'busy': false,
      'supported': ['hdf'],
      'values': {'hdf': hdf}
    };
Map<String, dynamic> extCaps() => {
      'schema': extensionSchema,
      'contractHash': extensionContractHash,
      'fields': [
        for (final e in extensionFields.entries)
          {
            'key': e.key,
            'min': e.value.min,
            'max': e.value.max,
            'supported': e.key == 'hdf',
            'persistence': e.value.runtime ? 'runtime' : 'persistent'
          }
      ]
    };

class MemoryPending implements ExtensionPendingStore {
  Map<String, Object?>? saved;
  bool fail = false;
  @override
  Future<Map<String, Object?>?> load() async => saved;
  @override
  Future<void> save(Map<String, Object?> value) async {
    if (fail) throw StateError('disk');
    saved = value;
  }

  @override
  Future<void> clear() async {
    saved = null;
  }
}

class ExtensionFake implements CompanionExtensionsApi {
  @override
  String? get bootId => '03' * 16;
  int submissions = 0, value = 0;
  bool uncertain = false;
  void Function()? afterRead;
  @override
  Future<ExtensionCapabilities> extensionCapabilities() async =>
      ExtensionCapabilities.fromJson(extCaps());
  @override
  Future<ExtensionSnapshot> extensionState() async {
    afterRead?.call();
    return ExtensionSnapshot.fromJson(extSnapshot(hdf: value));
  }

  @override
  Future<ExtensionReceipt> submitExtension(
      Map<String, Object?> operation) async {
    submissions++;
    if (uncertain) throw StateError('lost');
    value = operation['value'] as int;
    return ExtensionReceipt.fromJson({
      'requestId': operation['requestId'],
      'bootId': bootId,
      'status': 'committed',
      'snapshot': extSnapshot(hdf: value)
    });
  }

  @override
  Future<ExtensionReceipt> extensionOperation(String id) async =>
      ExtensionReceipt.fromJson(
          {'requestId': id, 'bootId': bootId, 'status': 'unknown'});
}

void main() {
  test('same-boot manual reconciliation cannot unlock an unresolved write',
      () async {
    final api = ExtensionFake()..uncertain = true, store = MemoryPending();
    final controller = CameraExtensionsController(
        api: api,
        store: store,
        instanceId: '01' * 16,
        bootstrap: () async {},
        blocked: () => false,
        onPending: (_) {});
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.set('hdf', 2);
    await controller.acknowledgeCurrentState();
    expect(controller.pending, isTrue);
    expect(store.saved, isNotNull);
    expect(api.submissions, 1);
  });

  test(
      'pending payload is durable before a single write; readback confirms value',
      () async {
    final api = ExtensionFake(), store = MemoryPending();
    final controller = CameraExtensionsController(
        api: api,
        store: store,
        instanceId: '01' * 16,
        bootstrap: () async {},
        blocked: () => false,
        onPending: (_) {});
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.set('hdf', 2);
    expect(api.submissions, 1);
    expect(controller.snapshot!.values['hdf'], 2);
    expect(store.saved, isNull);
    expect(controller.pending, isFalse);
  });
  test('gate changing during fresh read prevents the write', () async {
    var blocked = false;
    final api = ExtensionFake(), store = MemoryPending();
    final controller = CameraExtensionsController(
        api: api,
        store: store,
        instanceId: '01' * 16,
        bootstrap: () async {},
        blocked: () => blocked,
        onPending: (_) {});
    addTearDown(controller.dispose);
    await controller.refresh();
    api.afterRead = () => blocked = true;
    await controller.set('hdf', 2);
    expect(api.submissions, 0);
    expect(store.saved, isNull);
  });
  test('uncertain result persists across reload without submitting again',
      () async {
    final api = ExtensionFake()..uncertain = true, store = MemoryPending();
    final controller = CameraExtensionsController(
        api: api,
        store: store,
        instanceId: '01' * 16,
        bootstrap: () async {},
        blocked: () => false,
        onPending: (_) {});
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.set('hdf', 2);
    expect(controller.pending, isTrue);
    expect(store.saved, isNotNull);
    await controller.refresh();
    expect(api.submissions, 1);
    expect(controller.pending, isTrue);
  });
  test('failed durable recording cannot send a network write', () async {
    final api = ExtensionFake(), store = MemoryPending()..fail = true;
    final controller = CameraExtensionsController(
        api: api,
        store: store,
        instanceId: '01' * 16,
        bootstrap: () async {},
        blocked: () => false,
        onPending: (_) {});
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.set('hdf', 2);
    expect(api.submissions, 0);
    expect(controller.pending, isFalse);
  });
}
