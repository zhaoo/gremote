import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import '../../platform/device_api.g.dart';

class PairingIdentity {
  const PairingIdentity({required this.instanceId, required this.keyId});
  final String instanceId, keyId;
  @override
  String toString() => 'PairingIdentity($instanceId)';
}

abstract interface class PairingStore {
  Future<void> save(String instanceId, Uint8List keyBytes);
  Future<void> remove(String instanceId);
  Future<Uint8List> sign(String instanceId, Uint8List canonicalBytes);
}

class NativePairingStore implements PairingStore {
  NativePairingStore({CameraDeviceHostApi? api})
      : _api = api ?? CameraDeviceHostApi();
  final CameraDeviceHostApi _api;
  @override
  Future<void> save(String id, Uint8List key) =>
      _api.saveCompanionPairing(id, key);
  @override
  Future<void> remove(String id) => _api.removeCompanionPairing(id);
  @override
  Future<Uint8List> sign(String id, Uint8List bytes) =>
      _api.signCompanionRequest(id, bytes);
}

/// A credential provided by the camera hotspot lives only for this connection.
class HotspotPairingStore implements PairingStore {
  Uint8List? _key;
  String? _id;

  @override
  Future<void> save(String id, Uint8List key) async {
    clear();
    _id = id;
    _key = Uint8List.fromList(key);
  }

  @override
  Future<void> remove(String id) async {
    if (_id == id) clear();
  }

  void clear() {
    _key?.fillRange(0, _key!.length, 0);
    _key = null;
    _id = null;
  }

  @override
  Future<Uint8List> sign(String id, Uint8List bytes) async {
    final key = _key;
    if (_id != id || key == null) throw StateError('相机连接已断开');
    return Uint8List.fromList(Hmac(sha256, key).convert(bytes).bytes);
  }
}

Future<PairingIdentity> importPairing(
    Uint8List bytes, PairingStore store) async {
  if (bytes.isEmpty || bytes.length > 4096) {
    throw const FormatException('配对文件大小无效');
  }
  final value = jsonDecode(utf8.decode(bytes));
  final hex = RegExp(r'^[a-f0-9]{32}$');
  if (value is! Map ||
      value.length != 6 ||
      value['schema'] != 'm10v.companion-pairing/v1' ||
      value['protocol'] != 1 ||
      value['model'] != 'GR III' ||
      value['instanceId'] is! String ||
      !hex.hasMatch(value['instanceId'] as String) ||
      value['keyId'] is! String ||
      !hex.hasMatch(value['keyId'] as String) ||
      value['keyHex'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['keyHex'] as String)) {
    throw const FormatException('不支持的配对文件');
  }
  final key = Uint8List.fromList(List.generate(
      32,
      (i) => int.parse((value['keyHex'] as String).substring(i * 2, i * 2 + 2),
          radix: 16)));
  try {
    if (sha256.convert(key).toString().substring(0, 32) != value['keyId']) {
      throw const FormatException('配对文件校验失败');
    }
    await store.save(value['instanceId'] as String, key);
    return PairingIdentity(
        instanceId: value['instanceId'] as String,
        keyId: value['keyId'] as String);
  } finally {
    key.fillRange(0, key.length, 0);
  }
}

/// Only the active public identity is stored here. Secret keys stay native.
class PairingIdentityStorage {
  Future<File> _file() async => File(
      '${(await getApplicationSupportDirectory()).path}/companion-identity.json');
  Future<PairingIdentity?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final value = jsonDecode(await file.readAsString());
    if (value is! Map ||
        value.length != 2 ||
        value['instanceId'] is! String ||
        value['keyId'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['instanceId'] as String) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['keyId'] as String)) {
      return null;
    }
    return PairingIdentity(
        instanceId: value['instanceId'] as String,
        keyId: value['keyId'] as String);
  }

  Future<void> save(PairingIdentity value) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
        jsonEncode({'instanceId': value.instanceId, 'keyId': value.keyId}),
        flush: true);
    await temporary.rename(file.path);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
