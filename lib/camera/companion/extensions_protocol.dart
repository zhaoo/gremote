const extensionSchema = 'm10v.extensions/v1';
const extensionContractHash =
    '8014c8d909a7427519c41c524088912a426bb27a1ec7168e82f4659c5ba113cd';
const legacyExtensionContractHash =
    '9df047418574e23fd399a0c59491aecc9ea212dbf119a79ff29532aec6493628';
const supportedExtensionContractHashes = {
  extensionContractHash,
  legacyExtensionContractHash
};

class ExtensionField {
  const ExtensionField(this.label, this.group, this.min, this.max,
      {this.choices, this.unit = '', this.runtime = false});
  final String label, group, unit;
  final int min, max;
  final Map<int, String>? choices;
  final bool runtime;
  bool accepts(Object? value) => value is int && value >= min && value <= max;
  String display(int value) => choices?[value] ?? '$value$unit';
}

const _levels = {0: '关闭', 1: '弱', 2: '中', 3: '强'};
const _sizes = {0: '小', 1: '中', 2: '大'};
const _tones = {
  0: '标准',
  1: '鲜艳',
  2: '黑白',
  3: '柔和黑白',
  4: '硬调黑白',
  5: '高对比黑白',
  6: '负片',
  7: '正片',
  8: '留银冲洗',
  9: '复古',
  10: 'HDR 色调',
  11: '交叉冲洗',
  12: '胶卷槽 01',
  13: '胶卷槽 02',
  14: '胶卷槽 03',
  15: '胶卷槽 04',
  16: '胶卷槽 05',
  17: '胶卷槽 06',
  18: '胶卷槽 07',
  19: '胶卷槽 08',
  20: '胶卷槽 09',
  21: '胶卷槽 10'
};
const extensionFields = <String, ExtensionField>{
  'imprint': ExtensionField('胶卷印花', '效果', 0, 7, choices: {
    0: '关闭', 1: '猫鱼', 2: '樱花', 3: '彩虹', 4: '水母',
    5: '爪印', 6: '鹅', 7: '宝可梦'
  }),
  'quickSwitch': ExtensionField('快切', '功能', 0, 1,
      choices: {0: '关闭', 1: '开启'}, runtime: true),
  'quickSwitchA': ExtensionField('快切 A', '功能', 0, 21, choices: _tones),
  'quickSwitchB': ExtensionField('快切 B', '功能', 0, 21, choices: _tones),
  'hdf': ExtensionField('HDF', '效果', 0, 3, choices: _levels),
  'border':
      ExtensionField('边框', '效果', 0, 2, choices: {0: '关闭', 1: '拍立得', 2: '胶片'}),
  'grainMode': ExtensionField('颗粒', '效果', 0, 4,
      choices: {0: '跟随胶卷', 1: '关闭', 2: '弱', 3: '中', 4: '强'}),
  'grainSize':
      ExtensionField('颗粒尺寸', '效果', 0, 2, choices: {0: '细', 1: '标准', 2: '粗'}),
  'leakGain': ExtensionField('漏光', '效果', 0, 3, choices: _levels),
  'leakPosition':
      ExtensionField('漏光位置', '效果', 0, 2,
          choices: {0: '左侧', 1: '右侧', 2: '两侧'}),
  'leakSpread':
      ExtensionField('漏光范围', '效果', 0, 2, choices: {0: '窄', 1: '中', 2: '宽'}),
  'blurGain': ExtensionField('模糊', '效果', 0, 3, choices: _levels),
  'blurRange': ExtensionField('模糊范围', '效果', 0, 2, choices: _sizes),
  'stamp':
      ExtensionField('时间', '水印', 0, 2, choices: {0: '关闭', 1: '日期', 2: '日期与时间'}),
  'stampFormat': ExtensionField('日期格式', '水印', 0, 3, choices: {
    0: 'YYYY.MM.DD',
    1: 'DD.MM.YYYY',
    2: 'YYYY-MM-DD',
    3: 'YY.MM.DD'
  }),
  'stampCorner': ExtensionField('位置', '水印', 0, 3,
      choices: {0: '左上', 1: '右上', 2: '左下', 3: '右下'}),
  'stampColor': ExtensionField('颜色', '水印', 0, 3,
      choices: {0: '白色', 1: '橙色', 2: '红色', 3: '黄色'}),
  'filmNameStamp':
      ExtensionField('胶卷名称', '水印', 0, 1, choices: {0: '关闭', 1: '开启'}),
  'focalA': ExtensionField('第一档', '焦距', 28, 50, unit: ' mm'),
  'focalB': ExtensionField('第二档', '焦距', 28, 50, unit: ' mm'),
  'focalSlot': ExtensionField('当前焦距', '焦距', 0, 2,
      choices: {0: '第一档', 1: '第二档', 2: '原生 28 mm'}, runtime: true),
  'aspect': ExtensionField('画幅', '画幅', 0, 6,
      choices: {
        0: '3:2',
        3: '1:1',
        1: '4:3',
        2: '16:9',
        4: 'XPan',
        5: '6×7',
        6: 'Half 3:4'
      },
      runtime: true),
};

void _need(bool value) {
  if (!value) throw const FormatException('扩展设置协议不兼容');
}

bool extensionValueSupported(String contract, String key, Object? value) =>
    extensionFields[key]?.accepts(value) == true &&
    !(contract == legacyExtensionContractHash &&
        (key == 'imprint' || key == 'leakPosition' && (value as int) > 2));

String _hex(Map<String, dynamic> v, String key, int length) {
  final value = v[key];
  _need(value is String && RegExp('^[a-f0-9]{$length}\$').hasMatch(value));
  return value as String;
}

String _schema(Map<String, dynamic> v) {
  _need(v['schema'] == extensionSchema &&
      supportedExtensionContractHashes.contains(v['contractHash']));
  return v['contractHash'] as String;
}

class ExtensionCapabilities {
  ExtensionCapabilities.fromJson(Map<String, dynamic> v) {
    contractHash = _schema(v);
    _need(v['fields'] is List);
    final supported = <String>{}, seen = <String>{};
    for (final item in v['fields'] as List) {
      _need(item is Map);
      final field = Map<String, dynamic>.from(item as Map), key = field['key'];
      final expected = extensionFields[key];
      _need(key is String &&
          (contractHash != legacyExtensionContractHash || key != 'imprint') &&
          seen.add(key) &&
          expected != null &&
          field['min'] == expected.min &&
          field['max'] == (contractHash == legacyExtensionContractHash &&
              key == 'leakPosition' ? 2 : expected.max) &&
          field['supported'] is bool &&
          field['persistence'] ==
              (expected.runtime ? 'runtime' : 'persistent'));
      if (field['supported'] == true) supported.add(key as String);
    }
    _need(seen.length == extensionFields.length -
        (contractHash == legacyExtensionContractHash ? 1 : 0));
    this.supported = Set.unmodifiable(supported);
  }
  late final Set<String> supported;
  late final String contractHash;
  bool accepts(String key, Object? value) =>
      supported.contains(key) && extensionValueSupported(contractHash, key, value);
}

class ExtensionSnapshot {
  ExtensionSnapshot.fromJson(Map<String, dynamic> v) {
    contractHash = _schema(v);
    instanceId = _hex(v, 'instanceId', 32);
    buildId = _hex(v, 'buildId', 64);
    bootId = _hex(v, 'bootId', 32);
    revision = _hex(v, 'revision', 64);
    _need(v['busy'] is bool && v['supported'] is List && v['values'] is Map);
    busy = v['busy'] as bool;
    final keys = (v['supported'] as List);
    _need(keys.every((k) => k is String && extensionFields.containsKey(k)) &&
        keys.toSet().length == keys.length);
    supported = Set<String>.unmodifiable(keys.cast<String>());
    _need(contractHash != legacyExtensionContractHash ||
        !supported.contains('imprint'));
    final raw = Map<String, dynamic>.from(v['values'] as Map);
    _need(raw.length == supported.length && raw.keys.every(supported.contains));
    final values = <String, int>{};
    for (final e in raw.entries) {
      _need(extensionValueSupported(contractHash, e.key, e.value));
      values[e.key] = e.value as int;
    }
    this.values = Map.unmodifiable(values);
  }
  late final String instanceId, buildId, bootId, revision;
  late final String contractHash;
  late final bool busy;
  late final Set<String> supported;
  late final Map<String, int> values;
}

class ExtensionReceipt {
  ExtensionReceipt.fromJson(Map<String, dynamic> v) {
    requestId = _hex(v, 'requestId', 32);
    bootId = _hex(v, 'bootId', 32);
    _need(const {'queued', 'applying', 'committed', 'rejected', 'unknown'}
        .contains(v['status']));
    status = v['status'] as String;
    final raw = v['snapshot'];
    snapshot = raw == null
        ? null
        : ExtensionSnapshot.fromJson(Map<String, dynamic>.from(raw as Map));
    _need(status != 'committed' || snapshot != null);
    final error = v['code'];
    _need(error == null || error is String && error.length <= 48);
    code = error as String?;
  }
  late final String requestId, bootId, status;
  late final String? code;
  late final ExtensionSnapshot? snapshot;
}

abstract interface class CompanionExtensionsApi {
  String? get bootId;
  Future<ExtensionCapabilities> extensionCapabilities();
  Future<ExtensionSnapshot> extensionState();
  Future<ExtensionReceipt> submitExtension(Map<String, Object?> operation);
  Future<ExtensionReceipt> extensionOperation(String requestId);
}
