import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'companion_client.dart';
import 'extensions_protocol.dart';

abstract interface class ExtensionPendingStore {
  Future<Map<String, Object?>?> load();
  Future<void> save(Map<String, Object?> operation);
  Future<void> clear();
}

class SqliteExtensionPendingStore implements ExtensionPendingStore {
  SqliteExtensionPendingStore(this.db, this.instanceId);
  final Database db;
  final String instanceId;
  String get key => 'extension.pending.$instanceId';
  @override
  Future<Map<String, Object?>?> load() async {
    final rows =
        await db.query('app_kv', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final encoded = rows.single['value'] as String;
    if (encoded.length > 2048) throw const FormatException('未决设置记录损坏');
    return Map<String, Object?>.from(jsonDecode(encoded) as Map);
  }

  @override
  Future<void> save(Map<String, Object?> operation) async {
    await db.insert('app_kv', {'key': key, 'value': jsonEncode(operation)},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> clear() async {
    await db.delete('app_kv', where: 'key = ?', whereArgs: [key]);
  }
}

/// One field, one native journal operation. Never retries a submitted mutation.
class CameraExtensionsController extends ChangeNotifier {
  CameraExtensionsController(
      {required this.api,
      required this.store,
      required this.instanceId,
      required this.bootstrap,
      required this.blocked,
      required this.onPending,
      Future<void> Function()? wait})
      : wait = wait ??
            (() => Future<void>.delayed(const Duration(milliseconds: 250)));
  final CompanionExtensionsApi api;
  final ExtensionPendingStore store;
  final String instanceId;
  final Future<void> Function() bootstrap, wait;
  final bool Function() blocked;
  final void Function(bool) onPending;
  bool _alive = true, working = false, unsupported = false, _fresh = false;
  Map<String, Object?>? _operation;
  bool _unreadablePending = false;
  ExtensionCapabilities? capabilities;
  ExtensionSnapshot? snapshot;
  String? message;
  bool get pending => _operation != null || _unreadablePending;
  bool get canWrite =>
      _alive &&
      !working &&
      _fresh &&
      !unsupported &&
      !pending &&
      !blocked() &&
      snapshot != null &&
      !snapshot!.busy;
  void _changed() {
    if (_alive) notifyListeners();
  }

  void _identity(ExtensionSnapshot value) {
    if (value.instanceId != instanceId || value.bootId != api.bootId) {
      throw const CompanionException('sessionChanged');
    }
  }

  bool _allowed() => _alive && !blocked();
  void _guard() {
    if (!_allowed()) throw const CompanionException('busy');
  }

  String _error(Object e) {
    final code = e is CompanionException ? e.code : '';
    return const {
          'extensionsUnsupported': '请更新相机扩展固件和 SD 服务',
          'revisionConflict': '机身设置已变化，请重新选择',
          'busy': '请结束拍摄、程序或原图传输后重试',
          'unauthorized': '配对已失效，请重新配对',
          'identityMismatch': '相机身份不匹配',
          'sessionChanged': '连接已变化，请重新读取',
          'storeFailed': '保存失败，请重新读取',
          'readbackMismatch': '设置结果待核对',
          'invalidRecipe': '参数不受支持或所选胶卷槽为空'
        }[code] ??
        '操作未完成，请重新读取核对';
  }

  void _validatePending(Map<String, Object?> op) {
    final key = op['field'], value = op['value'];
    if (op.keys.toSet().difference({
          'requestId',
          'bootId',
          'contractHash',
          'baseRevision',
          'field',
          'value'
        }).isNotEmpty ||
        op.length != 6 ||
        key is! String ||
        extensionFields[key]?.accepts(value) != true ||
        op['contractHash'] != extensionContractHash ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch('${op['requestId']}') ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch('${op['bootId']}') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch('${op['baseRevision']}')) {
      throw const FormatException('未决设置记录损坏');
    }
  }

  Future<void> refresh() async {
    if (working || !_allowed()) return;
    working = true;
    _fresh = false;
    message = null;
    _changed();
    try {
      try {
        final saved = await store.load();
        if (saved != null) {
          _validatePending(saved);
          _operation = saved;
          onPending(true);
        }
      } catch (_) {
        _unreadablePending = true;
        onPending(true);
        rethrow;
      }
      _guard();
      await bootstrap();
      _guard();
      capabilities = await api.extensionCapabilities();
      _guard();
      final value = await api.extensionState();
      _guard();
      _identity(value);
      snapshot = value;
      _fresh = true;
      unsupported = false;
      if (pending) {
        if (_operation != null && _operation!['bootId'] == api.bootId) {
          await _resolve(
              await api.extensionOperation(_operation!['requestId'] as String));
        } else {
          message = '机身已重启，结果待核对';
        }
      }
    } catch (e) {
      unsupported =
          e is CompanionException && e.code == 'extensionsUnsupported';
      message = pending ? '结果待核对，请勿重复提交' : _error(e);
    } finally {
      working = false;
      _changed();
    }
  }

  Future<void> set(String field, int value, {String? expectedRevision}) async {
    final base = snapshot;
    if (!canWrite ||
        base == null ||
        capabilities?.supported.contains(field) != true ||
        !base.supported.contains(field) ||
        extensionFields[field]?.accepts(value) != true) return;
    if (base.values[field] == value) return;
    working = true;
    _fresh = false;
    message = null;
    _changed();
    var recorded = false, submitted = false;
    try {
      _guard();
      final current = await api.extensionState();
      _guard();
      _identity(current);
      snapshot = current;
      if (current.busy) throw const CompanionException('busy');
      if (current.revision != (expectedRevision ?? base.revision) ||
          current.bootId != base.bootId) {
        throw const CompanionException('revisionConflict');
      }
      final operation = <String, Object?>{
        'requestId': List.generate(
            16,
            (_) => Random.secure()
                .nextInt(256)
                .toRadixString(16)
                .padLeft(2, '0')).join(),
        'bootId': current.bootId,
        'contractHash': extensionContractHash,
        'baseRevision': current.revision,
        'field': field,
        'value': value
      };
      await store.save(operation);
      recorded = true;
      _operation = Map.unmodifiable(operation);
      onPending(true);
      _guard();
      submitted = true;
      var receipt = await api.submitExtension(operation);
      for (var i = 0;
          i < 7 && const {'queued', 'applying'}.contains(receipt.status);
          i++) {
        _guard();
        await wait();
        _guard();
        receipt =
            await api.extensionOperation(operation['requestId'] as String);
      }
      await _resolve(receipt);
    } catch (e) {
      if (recorded && !submitted) {
        try {
          await _clear();
          message = _error(e);
        } catch (_) {
          message = '结果待核对，请重新读取';
        }
      } else {
        message = pending ? '结果待核对，请勿重复提交' : _error(e);
      }
    } finally {
      working = false;
      _changed();
    }
  }

  Future<void> _clear() async {
    await store.clear();
    _operation = null;
    _unreadablePending = false;
    onPending(false);
  }

  Future<void> _resolve(ExtensionReceipt receipt) async {
    final operation = _operation;
    if (operation == null) return;
    if (receipt.requestId != operation['requestId'] ||
        receipt.bootId != operation['bootId']) {
      throw const CompanionException('identityMismatch');
    }
    if (receipt.status == 'rejected') {
      await _clear();
      message = _error(CompanionException(receipt.code ?? 'storeFailed'));
      return;
    }
    if (receipt.status != 'committed') {
      message = '结果待核对，请勿重复提交';
      return;
    }
    final committed = receipt.snapshot!;
    _identity(committed);
    if (committed.values[operation['field']] != operation['value']) {
      throw const CompanionException('readbackMismatch');
    }
    _guard();
    final fresh = await api.extensionState();
    _guard();
    _identity(fresh);
    if (fresh.busy || fresh.values[operation['field']] != operation['value']) {
      throw const CompanionException('readbackMismatch');
    }
    snapshot = fresh;
    _fresh = true;
    await _clear();
    message = '已保存';
  }

  /// Only after explicit user acknowledgement; clears the draft, never writes.
  Future<void> acknowledgeCurrentState() async {
    if (working || !pending || !_allowed()) return;
    working = true;
    _changed();
    try {
      _guard();
      final fresh = await api.extensionState();
      _guard();
      _identity(fresh);
      if (fresh.busy) throw const CompanionException('busy');
      snapshot = fresh;
      _fresh = true;
      if (_operation != null && _operation!['bootId'] == fresh.bootId) {
        message = '本次开机仍有未决操作，请重启相机后再核对';
        return;
      }
      await _clear();
      message = '已核对当前设置';
    } catch (e) {
      message = _error(e);
    } finally {
      working = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }
}
