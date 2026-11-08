import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../film/model/film_recipe.dart';
import '../../film/store/sync_repository.dart';
import 'companion_client.dart';
import 'companion_protocol.dart';
import 'sync_state.dart';
import 'three_way_merge.dart';
import 'film_transfer.dart';
import 'camera_film_catalog.dart';

String companionErrorMessage(Object error) {
  final code = error is CompanionException
      ? error.code
      : error is PlatformException
          ? error.code
          : '';
  return const {
        'unauthorized': 'M10V 连接已失效，请重新连接相机 Wi-Fi',
        'bridgeUnavailable': '相机暂不支持无线装卷',
        'companionUnsupported': '当前平台暂不支持相机无线装卷',
        'busy': '相机正忙，请稍后确认',
        'revisionConflict': '机身配置已变化，请重新核对',
        'incompatibleRenderer': '胶卷版本不匹配，请使用配套版本',
        'sessionChanged': '相机连接已变化，请重新读取',
        'resultUnknown': '结果待核对',
        'identityMismatch': '相机身份校验失败',
        'unauthenticatedResponse': '响应校验失败，请重新连接'
      }[code] ??
      '暂时无法完成，请检查连接后重试';
}

class _Pending {
  _Pending(this.payload);
  final Map<String, Object?> payload;
  Map<String, Object?> get wire => wireMap(payload['wire']);
  Map<String, Object?> get expected => wireMap(payload['expectedConfig']);
  String get id => wire['requestId'] as String;
  String get boot => wire['bootId'] as String;
  String get stage => payload['stage'] as String;
  int? get active => payload['expectedActiveSlot'] as int?;
}

/// The current prepared intent, after controller target normalization.
typedef PreparedCompanionLoad = ({int slot, FilmRecipe recipe, bool activate});

class CompanionSyncController extends ChangeNotifier {
  CompanionSyncController(
      {required this.api,
      required this.repository,
      required String catalogHash,
      required String rendererHash,
      CameraFilmCatalog? cameraCatalog,
      this.resolveCameraCatalog,
      bool Function()? isWriteBlocked,
      Future<void> Function()? wait,
      Future<void> Function(FilmRecipe)? keepLocalRecipe})
      : _fallbackCatalogHash = catalogHash,
        _fallbackRendererHash = rendererHash,
        _cameraCatalog = cameraCatalog,
        isWriteBlocked = isWriteBlocked ?? (() => false),
        _wait =
            wait ?? (() => Future<void>.delayed(const Duration(seconds: 2))),
        _keepLocalRecipe = keepLocalRecipe;
  final CompanionApi api;
  final SyncRepository repository;
  final String _fallbackCatalogHash, _fallbackRendererHash;
  CameraFilmCatalog? _cameraCatalog;
  CameraFilmCatalog? get cameraCatalog => _cameraCatalog;
  String get catalogHash => cameraCatalog?.hash ?? _fallbackCatalogHash;
  String get rendererHash =>
      cameraCatalog?.rendererHash ?? _fallbackRendererHash;
  final CameraFilmCatalog? Function(CompanionCapabilities)?
      resolveCameraCatalog;
  bool _unknownCameraProfile = false;
  Map<String, dynamic> get contract =>
      cameraCatalog?.contract ??
      (resolveCameraCatalog == null ? companionContract : cameraContract);

  CompanionCapabilities _negotiate(CompanionCapabilities caps) {
    final resolver = resolveCameraCatalog;
    if (resolver == null) return caps;
    final selected = resolver(caps);
    // Even an injected resolver cannot register an unpinned camera identity.
    final trusted =
        resolveCameraFilmProfile(caps.catalogHash, caps.rendererHash);
    final next = trusted != null &&
            selected?.hash == caps.catalogHash &&
            selected?.rendererHash == caps.rendererHash
        ? selected
        : null;
    final changed = next?.hash != _cameraCatalog?.hash ||
        next?.rendererHash != _cameraCatalog?.rendererHash;
    _unknownCameraProfile = next == null;
    _cameraCatalog = next;
    if (changed) {
      _base = null;
      _local = null;
      _slot = null;
      _recipe = null;
      _film = null;
      _activate = false;
      _set(state.copyWith(
          readOnly: true, stale: true, hasPreparedLoad: false, merge: null));
    }
    return CompanionCapabilities.fromJson(Map<String, dynamic>.from(caps.wire),
        contract: contract);
  }

  int get slotCount => contract['slotCount'] as int;
  PreparedCompanionLoad? get preparedLoad {
    if (!_alive ||
        _preparing ||
        !state.hasPreparedLoad ||
        _slot == null ||
        _recipe == null) {
      return null;
    }
    return (slot: _slot!, recipe: _recipe!, activate: _activate);
  }

  int? get preparedSlot => preparedLoad?.slot;
  final bool Function() isWriteBlocked;
  final Future<void> Function() _wait;
  final Future<void> Function(FilmRecipe)? _keepLocalRecipe;
  CompanionSyncState _state = const CompanionSyncState();
  CompanionSyncState get state => _state;
  bool _alive = true, _working = false, _active = true, _preparing = false;
  int _epoch = 0;
  Future<void>? _refreshing;
  CompanionSnapshot? _base;
  Map<String, Object?>? _local;
  _Pending? _pending;
  Map<String, Object?>? _uploadPending;
  bool get _hasPending => _pending != null || _uploadPending != null;
  String? get _pendingBoot =>
      _pending?.boot ?? _uploadPending?['bootId'] as String?;
  int? _slot;
  FilmRecipe? _recipe;
  FilmTransfer? _film;
  bool _activate = false;
  void _set(CompanionSyncState next) {
    if (!_alive) return;
    _state = next;
    notifyListeners();
  }

  bool _current(int epoch) => _alive && epoch == _epoch;
  void setActive(bool value) {
    _active = value;
  }

  void disconnected() {
    if (!_alive) return;
    _epoch++;
    api.invalidate();
    _set(state.copyWith(
        connectionStatus: SyncConnectionStatus.offline,
        stale: true,
        readOnly: true,
        message: state.pending ? '结果待核对，请重新连接相机' : '请连接相机 Wi-Fi',
        operationStatus: state.pending
            ? SyncOperationStatus.unknown
            : state.operationStatus));
  }

  @override
  void dispose() {
    if (!_alive) return;
    _alive = false;
    _epoch++;
    api.invalidate();
    super.dispose();
  }

  String _id() => List.generate(16,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
  Future<void> refresh() {
    if (!_alive) return Future.value();
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    if (_working) return;
    final epoch = _epoch;
    // Keep a fresh snapshot usable during routine background reads.
    if (state.snapshot == null || state.stale) {
      _set(state.copyWith(connectionStatus: SyncConnectionStatus.connecting));
    }
    try {
      var caps = state.capabilities;
      if (caps == null || api.bootId == null) {
        caps = await api.capabilities();
        if (!_current(epoch)) return;
      }
      caps = _negotiate(caps);
      if (!caps.supports('readState')) {
        _set(state.copyWith(
            capabilities: caps,
            connectionStatus: SyncConnectionStatus.unsupported,
            readOnly: true,
            stale: true,
            message: '相机暂不支持无线装卷；离线试卷和数字胶卷仍可使用'));
        return;
      }
      CompanionSnapshot snapshot;
      try {
        snapshot = await api.state();
      } on CompanionException catch (error) {
        if (error.code != 'unauthorized' && error.code != 'sessionChanged') {
          rethrow;
        }
        api.invalidate();
        caps = _negotiate(await api.capabilities());
        snapshot = await api.state();
      }
      if (!_current(epoch)) return;
      final rows = await repository.unresolved(caps.instanceId);
      if (!_current(epoch)) return;
      if (!_hasPending && rows.isNotEmpty) {
        final raw = jsonDecode(rows.first['payload_json'] as String);
        if ((raw as Map)['kind'] == 'upload') {
          _uploadPending = wireMap(raw);
        } else {
          _pending = _Pending(wireMap(raw));
        }
      }
      if (_base == null) {
        final saved = await repository.baseline(caps.instanceId);
        if (!_current(epoch)) return;
        try {
          _base = saved == null
              ? snapshot
              : CompanionSnapshot.fromJson(saved, contract: contract);
          if (_base!.wire['catalogHash'] != catalogHash ||
              _base!.wire['rendererHash'] != rendererHash) _base = snapshot;
        } on FormatException {
          _base = snapshot;
        }
      }
      final compatible = !_unknownCameraProfile &&
          caps.compatibleWith(catalogHash, rendererHash) &&
          snapshot.wire['catalogHash'] == catalogHash &&
          snapshot.wire['rendererHash'] == rendererHash &&
          !snapshot.hasUnknownFields &&
          knownCompanionConfig(snapshot.config, contract: contract) &&
          snapshot.fresh &&
          caps.supports('writeState');
      final reboot = _hasPending && _pendingBoot != snapshot.bootId;
      var next = state.copyWith(
          capabilities: caps,
          snapshot: snapshot,
          stale: !snapshot.fresh,
          readOnly: !compatible,
          connectionStatus: !caps.supports('readState')
              ? SyncConnectionStatus.unsupported
              : snapshot.busy
                  ? SyncConnectionStatus.busy
                  : SyncConnectionStatus.ready,
          canRetryOriginal: false,
          rebootNeedsConfirmation: reboot);
      if (_hasPending) {
        next = next.copyWith(
            operationStatus: SyncOperationStatus.unknown,
            message: reboot ? '相机已重启，旧操作结果待确认；不会自动重放' : '有操作结果待核对');
      } else if (_local != null) {
        final merge = threeWayMerge(
            base: _base!.config,
            local: _local!,
            remote: snapshot.config,
            capabilities: caps);
        next = next.copyWith(
            merge: merge,
            operationStatus: merge.conflicts.isEmpty
                ? SyncOperationStatus.draft
                : SyncOperationStatus.conflict,
            message: merge.conflicts.isEmpty ? '请核对差异后确认' : '机身和手机修改了同一参数，请选择');
      } else {
        _base = snapshot;
        await repository.saveBaseline(caps.instanceId, snapshot.wire);
        if (!_current(epoch)) return;
        next = next.copyWith(
            message: compatible
                ? '已读取机身 $slotCount 槽配置'
                : _unknownCameraProfile
                    ? '配置仅供查看，此机身版本尚未受信任，请更新 App 或使用配套版本'
                    : '配置仅供查看，当前组件或配方版本不支持写入',
            operationStatus:
                state.operationStatus == SyncOperationStatus.synced &&
                        state.snapshot?.revision == snapshot.revision
                    ? SyncOperationStatus.synced
                    : SyncOperationStatus.draft);
      }
      _set(next);
    } catch (error) {
      if (!_current(epoch)) return;
      _set(state.copyWith(
          connectionStatus: SyncConnectionStatus.error,
          stale: true,
          readOnly: true,
          message: companionErrorMessage(error)));
    }
  }

  Map<String, Object?> _recipeSlot(FilmRecipe recipe) {
    final parameters = recipe.resolvedParameters;
    return {
      'filmId': recipe.filmId,
      'parameters': parameters,
      'customHash': recipe.customHash
    };
  }

  Future<void> prepareLoad(
      {required int slot,
      required FilmRecipe recipe,
      required bool activate,
      FilmTransfer? film}) async {
    if (!_alive || _working || _preparing || _hasPending) {
      throw const CompanionException('busy');
    }
    if (slot < 0 || slot >= slotCount) throw const FormatException('槽位无效');
    _preparing = true;
    try {
      await refresh();
      if (!_alive) return;
      if (state.readOnly ||
          state.snapshot == null ||
          state.capabilities == null ||
          (cameraCatalog == null &&
              (recipe.catalogHash != catalogHash ||
                  recipe.rendererHash != rendererHash))) {
        throw const CompanionException('incompatibleRenderer');
      }
      if (cameraCatalog != null) {
        final existing = state.snapshot!.slots
            .indexWhere((s) => s['filmId'] == recipe.filmId);
        if (existing >= 0) {
          slot = existing;
        } else {
          // Current schema2 native state requires occupied slots before empties.
          final firstEmpty =
              state.snapshot!.slots.indexWhere((s) => s['filmId'] == 0);
          if (firstEmpty >= 0 && slot > firstEmpty) slot = firstEmpty;
        }
        recipe = cameraCatalog!.forTarget(recipe, state.snapshot!.slots[slot]);
      }
      _slot = slot;
      _recipe = recipe;
      _film = film;
      _activate = activate;
      final local = Map<String, Object?>.from(_base!.config),
          slots = List<Object?>.from(local['slots'] as List);
      slots[slot] = _recipeSlot(recipe);
      local['slots'] = slots;
      _local = wireMap(local);
      final merge = threeWayMerge(
          base: _base!.config,
          local: _local!,
          remote: state.snapshot!.config,
          capabilities: state.capabilities!);
      _set(state.copyWith(
          merge: merge,
          hasPreparedLoad: true,
          operationStatus: merge.conflicts.isEmpty
              ? SyncOperationStatus.draft
              : SyncOperationStatus.conflict,
          message: merge.conflicts.isEmpty
              ? '请确认槽位和差异；浏览不会改变相机'
              : '同一参数发生冲突，请选择手机或机身配置'));
    } finally {
      _preparing = false;
    }
  }

  Future<void> resolve(Map<String, ConflictChoice> choices) async {
    final merge = state.merge;
    if (merge == null || _working) return;
    _working = true;
    try {
      final epoch = _epoch, resolved = merge.resolve(choices);
      if (resolved.resolved && resolved.keepLocalSlots.isNotEmpty) {
        if (_keepLocalRecipe == null) {
          throw const CompanionException('localSaveUnavailable');
        }
        for (final slot in resolved.keepLocalSlots) {
          final raw = (_local!['slots'] as List)[slot] as Map;
          final kept = <String, dynamic>{
            'schemaVersion': 1,
            ...Map<String, dynamic>.from(raw),
            'catalogHash': catalogHash,
            'rendererHash': rendererHash,
            'name': _recipe?.name ?? '保留的手机配方'
          };
          await _keepLocalRecipe(cameraCatalog == null
              ? FilmRecipe.fromJson(kept)
              : CameraFilmRecipe.fromJson(kept));
          if (!_current(epoch)) return;
        }
        if (resolved.keepLocalSlots.contains(_slot)) _activate = false;
      }
      _local = resolved.merged;
      _set(state.copyWith(
          merge: resolved,
          operationStatus: resolved.resolved
              ? SyncOperationStatus.draft
              : SyncOperationStatus.conflict,
          message: resolved.keepLocalSlots.isNotEmpty
              ? '手机配方已单独保留，机身槽位不变'
              : '冲突选择已保留，请确认差异'));
    } finally {
      _working = false;
    }
  }

  List<Map<String, Object?>> _patch(
      Map<String, Object?> remote, Map<String, Object?> desired) {
    if (canonicalJson(remote['globals']) != canonicalJson(desired['globals'])) {
      throw const CompanionException('unsupportedGlobalWrite');
    }
    final changes = <Map<String, Object?>>[],
        before = remote['slots'] as List,
        after = desired['slots'] as List;
    for (var slot = 0; slot < slotCount; slot++) {
      if (canonicalJson(before[slot]) == canonicalJson(after[slot])) continue;
      final value = wireMap(after[slot]);
      changes.add({
        'slot': slot,
        'filmId': value['filmId'],
        for (final e in wireMap(value['parameters']).entries)
          if (!(contract['readOnlyParameters'] as List? ?? []).contains(e.key))
            e.key: e.value,
        if (value['customHash'] != null) 'customHash': value['customHash']
      });
    }
    return changes;
  }

  bool _blocked() {
    if (isWriteBlocked() || state.snapshot?.busy == true || !_active) {
      _set(state.copyWith(
          connectionStatus: SyncConnectionStatus.busy,
          message: '拍摄、传输或相机正忙，请稍后确认'));
      return true;
    }
    return false;
  }

  Future<void> confirm() async {
    if (!_alive ||
        _working ||
        _hasPending ||
        !state.hasPreparedLoad ||
        state.merge == null ||
        !state.merge!.resolved ||
        state.merge!.readOnly ||
        state.readOnly) return;
    if (_blocked()) return;
    _working = true;
    _set(state.copyWith(canRetryOriginal: false));
    final epoch = _epoch;
    try {
      final fresh = await api.state();
      if (!_current(epoch)) return;
      if (!fresh.fresh ||
          fresh.instanceId != state.snapshot!.instanceId ||
          fresh.wire['catalogHash'] != catalogHash ||
          fresh.wire['rendererHash'] != rendererHash ||
          fresh.hasUnknownFields ||
          !knownCompanionConfig(fresh.config, contract: contract)) {
        _set(state.copyWith(
            snapshot: fresh,
            stale: !fresh.fresh,
            readOnly: true,
            message: '机身状态暂不可写，请重新读取'));
        return;
      }
      if (fresh.bootId != state.snapshot!.bootId ||
          fresh.revision != state.snapshot!.revision) {
        _set(state.copyWith(
            snapshot: fresh,
            stale: false,
            merge: threeWayMerge(
                base: _base!.config,
                local: _local!,
                remote: fresh.config,
                capabilities: state.capabilities!),
            operationStatus: SyncOperationStatus.conflict,
            message: '机身配置已变化，请重新核对并确认'));
        return;
      }
      if (fresh.busy || isWriteBlocked() || !_active) {
        _set(state.copyWith(
            snapshot: fresh,
            connectionStatus: SyncConnectionStatus.busy,
            message: '相机正忙，请稍后确认'));
        return;
      }
      final desired = state.merge!.merged;
      final patch = _patch(fresh.config, desired);
      if (patch.isNotEmpty) {
        if (_recipe!.customHash != null) {
          final target = wireMap((desired['slots'] as List)[_slot!]);
          final current = fresh.slots[_slot!];
          if (current['customHash'] != target['customHash']) {
            if (_film == null ||
                _film!.contentHash != _recipe!.customHash ||
                _film!.stableId != _recipe!.filmId) {
              throw const CompanionException('filmDataRequired');
            }
            if (!state.capabilities!.supports('uploadFilm')) {
              throw const CompanionException('bridgeUnavailable');
            }
            await _upload(_film!, _slot!, epoch);
            if (!_current(epoch) ||
                state.operationStatus == SyncOperationStatus.unknown) return;
          }
        }
        final ok =
            await _execute(fresh, desired, patch, null, 'install', epoch);
        if (!ok || !_current(epoch)) return;
      } else {
        _base = fresh;
        await repository.saveBaseline(fresh.instanceId, fresh.wire);
        if (!_current(epoch)) return;
        _set(state.copyWith(snapshot: fresh));
      }
      if (_activate && state.snapshot!.activeSlot != _slot) {
        if (_blocked()) {
          _set(state.copyWith(
              operationStatus: SyncOperationStatus.failed,
              message: '已装入，切换失败'));
          return;
        }
        await _execute(state.snapshot!, desired, [], _slot, 'activate', epoch);
        if (!_current(epoch)) return;
        if (state.operationStatus == SyncOperationStatus.failed) {
          _set(state.copyWith(message: '已装入，切换失败'));
        }
      } else {
        _local = null;
        _set(state.copyWith(
            operationStatus: SyncOperationStatus.synced,
            connectionStatus: SyncConnectionStatus.ready,
            hasPreparedLoad: false,
            merge: null,
            message: '已同步，以相机读回为准'));
      }
    } catch (error) {
      if (!_current(epoch)) return;
      _set(state.copyWith(
          operationStatus: !_hasPending
              ? SyncOperationStatus.failed
              : SyncOperationStatus.unknown,
          message:
              !_hasPending ? companionErrorMessage(error) : '结果待核对，请勿重复装卷'));
      if (_hasPending) await _persist('unknown');
    } finally {
      _working = false;
    }
  }

  void _checkUploadReceipt(FilmUploadReceipt receipt) {
    final expected = wireMap(_uploadPending!['metadata']);
    if (receipt.uploadId != _uploadPending!['uploadId'] ||
        receipt.wire['contentHash'] != expected['contentHash'] ||
        receipt.wire['targetSlot'] != expected['targetSlot'] ||
        receipt.wire['stableId'] != expected['stableId']) {
      throw const CompanionException('identityMismatch');
    }
  }

  Future<void> _upload(FilmTransfer film, int slot, int epoch) async {
    _set(state.copyWith(
        operationStatus: SyncOperationStatus.applying,
        message: '正在传送胶卷数据',
        uploadBytes: 0));
    final metadata = FilmUploadMetadata(
        stableId: film.stableId,
        targetSlot: slot,
        rendererHash: film.rendererHash,
        contentHash: film.contentHash);
    var receipt = await api.stageFilm(metadata);
    if (!_current(epoch)) return;
    for (var index = receipt.receivedBytes ~/ 4096; index < 3; index++) {
      if (!_active || isWriteBlocked()) throw const CompanionException('busy');
      receipt =
          await api.sendFilmChunk(receipt.uploadId, index, film.chunk(index));
      if (!_current(epoch)) return;
      _set(state.copyWith(uploadBytes: receipt.receivedBytes));
    }
    if (!_active || isWriteBlocked()) throw const CompanionException('busy');
    _uploadPending = wireMap({
      'kind': 'upload',
      'bootId': state.snapshot!.bootId,
      'uploadId': receipt.uploadId,
      'metadata': metadata.toJson()
    });
    await _persist('verifying');
    if (!_current(epoch)) return;
    for (var count = 0; count < 8; count++) {
      if (!_active || isWriteBlocked()) throw const CompanionException('busy');
      receipt = await api.verifyFilm(receipt.uploadId);
      if (!_current(epoch)) return;
      if (receipt.status == 'verified') {
        _checkUploadReceipt(receipt);
        await _persist('committed');
        if (!_current(epoch)) return;
        _uploadPending = null;
        return;
      }
      if (receipt.status == 'failed') {
        await _persist('failed');
        if (!_current(epoch)) return;
        _uploadPending = null;
        throw const CompanionException('storeFailed');
      }
      if (receipt.status == 'failed' || receipt.status == 'unknown') {
        throw const CompanionException('resultUnknown');
      }
      _set(state.copyWith(
          operationStatus: SyncOperationStatus.verifying, message: '正在校验胶卷数据'));
      await _wait();
    }
    throw const CompanionException('resultUnknown');
  }

  Future<bool> _execute(
      CompanionSnapshot base,
      Map<String, Object?> desired,
      List<Map<String, Object?>> patch,
      int? active,
      String stage,
      int epoch) async {
    final wire = <String, Object?>{
      'protocol': 1,
      'requestId': _id(),
      'bootId': base.bootId,
      'baseRevision': base.revision,
      'catalogHash': catalogHash,
      'rendererHash': rendererHash,
      'patch': patch,
      'activateSlot': active
    };
    _pending = _Pending(wireMap({
      'wire': wire,
      'expectedConfig': desired,
      'expectedActiveSlot': active,
      'stage': stage
    }));
    await _persist('queued');
    if (!_current(epoch)) return false;
    if (!_active || isWriteBlocked()) {
      await _persist('failed');
      if (!_current(epoch)) return false;
      _pending = null;
      _set(state.copyWith(
          operationStatus: SyncOperationStatus.failed,
          message: '相机正忙或页面已离开，请重新确认'));
      return false;
    }
    _set(state.copyWith(
        operationStatus: SyncOperationStatus.queued,
        message: stage == 'activate' ? '已装入，正在切换当前胶卷' : '配置已排队，等待相机确认'));
    final receipt = await api.submit(wire);
    if (!_current(epoch)) return false;
    return _pollReceipt(receipt, epoch);
  }

  Future<void> _persist(String status) async {
    if (_uploadPending != null) {
      await repository.saveOperation(
          requestId: 'upload:${_uploadPending!['uploadId']}',
          instanceId: state.capabilities!.instanceId,
          payload: _uploadPending!,
          status: status);
      return;
    }
    final pending = _pending;
    if (pending == null) return;
    await repository.saveOperation(
        requestId: pending.id,
        instanceId: state.capabilities!.instanceId,
        payload: pending.payload,
        status: status);
  }

  Future<bool> _pollReceipt(CompanionOperationReceipt first, int epoch) async {
    var receipt = first;
    for (var count = 0; count < 8; count++) {
      if (!_current(epoch)) return false;
      if (!_active) {
        await _unknown(epoch);
        return false;
      }
      if (receipt.status == CompanionOperationStatus.committed) {
        _set(state.copyWith(
            operationStatus: SyncOperationStatus.verifying,
            message: '正在核对机身读回'));
        final actual = await api.state();
        if (!_current(epoch)) return false;
        final expected = _pending!, proof = receipt.snapshot!;
        if (receipt.bootId != expected.boot ||
            actual.bootId != expected.boot ||
            actual.instanceId != state.capabilities!.instanceId ||
            proof.instanceId != actual.instanceId ||
            !actual.fresh ||
            !proof.fresh ||
            actual.hasUnknownFields ||
            proof.hasUnknownFields ||
            actual.wire["catalogHash"] != catalogHash ||
            actual.wire["rendererHash"] != rendererHash ||
            actual.revision != proof.revision ||
            actual.configHash != proof.configHash ||
            canonicalJson(actual.config) != canonicalJson(expected.expected) ||
            canonicalJson(proof.config) != canonicalJson(expected.expected) ||
            (expected.active != null &&
                (actual.activeSlot != expected.active ||
                    proof.activeSlot != expected.active))) {
          await _unknown(epoch);
          return false;
        }
        await _persist('committed');
        if (!_current(epoch)) return false;
        await repository.saveBaseline(actual.instanceId, actual.wire);
        if (!_current(epoch)) return false;
        _base = actual;
        _pending = null;
        _local = null;
        _set(state.copyWith(
            snapshot: actual,
            operationStatus: SyncOperationStatus.synced,
            connectionStatus: actual.busy
                ? SyncConnectionStatus.busy
                : SyncConnectionStatus.ready,
            stale: false,
            hasPreparedLoad: false,
            merge: null,
            message: '已同步，以相机读回为准'));
        return true;
      }
      if (receipt.status == CompanionOperationStatus.rejected) {
        await _persist('failed');
        if (!_current(epoch)) return false;
        final activation = _pending!.stage == 'activate';
        _pending = null;
        _set(state.copyWith(
            operationStatus: SyncOperationStatus.failed,
            message: activation
                ? '已装入，切换失败'
                : companionErrorMessage(
                    CompanionException(receipt.errorCode ?? 'storeFailed'))));
        return false;
      }
      if (receipt.status == CompanionOperationStatus.unknown || !_active) {
        await _unknown(epoch);
        return false;
      }
      _set(state.copyWith(
          operationStatus: receipt.status == CompanionOperationStatus.queued
              ? SyncOperationStatus.queued
              : SyncOperationStatus.applying));
      await _persist(receipt.status.name);
      await _wait();
      if (!_current(epoch)) return false;
      receipt = await api.operation(_pending!.id);
    }
    await _unknown(epoch);
    return false;
  }

  Future<void> _unknown(int epoch) async {
    await _persist('unknown');
    if (!_current(epoch)) return;
    _set(state.copyWith(
        operationStatus: SyncOperationStatus.unknown,
        message:
            _pending?.stage == 'activate' ? '已装入，切换结果待核对' : '结果待核对，请勿重复装卷'));
  }

  Future<void> reconcileUnknown() async {
    if (!_alive || _working || !_hasPending) return;
    _working = true;
    _set(state.copyWith(canRetryOriginal: false));
    final epoch = _epoch;
    try {
      final fresh = await api.state();
      if (!_current(epoch)) return;
      if (fresh.bootId != _pendingBoot) {
        _set(state.copyWith(
            snapshot: fresh,
            operationStatus: SyncOperationStatus.unknown,
            rebootNeedsConfirmation: true,
            message: '相机已重启，旧操作结果待确认；不会自动重放'));
        return;
      }
      if (_uploadPending != null) {
        final receipt =
            await api.filmUpload(_uploadPending!['uploadId'] as String);
        if (!_current(epoch)) return;
        _checkUploadReceipt(receipt);
        if (receipt.status == 'verified' ||
            receipt.status == 'failed' ||
            receipt.status == 'receiving') {
          await _persist(receipt.status == 'verified'
              ? 'committed'
              : receipt.status == 'failed'
                  ? 'failed'
                  : 'abandoned');
          if (!_current(epoch)) return;
          _uploadPending = null;
          _local = null;
          _set(state.copyWith(
              operationStatus: SyncOperationStatus.draft,
              hasPreparedLoad: false,
              merge: null,
              message: receipt.status == 'verified'
                  ? '胶卷数据已验证；请重新选择槽位并确认装入'
                  : '胶卷尚未验证；请重新选择数据并确认'));
          return;
        }
        await _unknown(epoch);
        return;
      }
      try {
        await _pollReceipt(await api.operation(_pending!.id), epoch);
      } on CompanionException catch (error) {
        if (error.code != 'resultUnknown') rethrow;
        if (!_current(epoch)) return;
        await _unknown(epoch);
        if (!_current(epoch)) return;
        final retry = _canRetry(fresh);
        _set(state.copyWith(
            snapshot: fresh,
            canRetryOriginal: retry,
            message: retry ? '相机没有可查询的回执；可确认后以原操作编号重试' : '结果待核对，当前配置不允许重试原操作'));
      }
    } catch (error) {
      if (_current(epoch)) await _unknown(epoch);
    } finally {
      _working = false;
    }
  }

  bool _canRetry(CompanionSnapshot fresh) {
    final pending = _pending, caps = state.capabilities;
    return pending != null &&
        caps != null &&
        _active &&
        !isWriteBlocked() &&
        !state.readOnly &&
        caps.supports('writeState') &&
        caps.compatibleWith(catalogHash, rendererHash) &&
        fresh.instanceId == caps.instanceId &&
        fresh.bootId == pending.boot &&
        fresh.revision == pending.wire['baseRevision'] &&
        pending.wire['catalogHash'] == catalogHash &&
        pending.wire['rendererHash'] == rendererHash &&
        fresh.fresh &&
        !fresh.busy &&
        fresh.wire['catalogHash'] == catalogHash &&
        fresh.wire['rendererHash'] == rendererHash &&
        !fresh.hasUnknownFields &&
        knownCompanionConfig(fresh.config, contract: contract);
  }

  /// Explicit user confirmation only. Never invent a replacement request ID.
  Future<void> retryOriginalOperation() async {
    if (!_alive || _working || !state.canRetryOriginal || _pending == null) {
      return;
    }
    _working = true;
    final epoch = _epoch;
    _set(state.copyWith(canRetryOriginal: false));
    try {
      final fresh = await api.state();
      if (!_current(epoch)) return;
      if (!_canRetry(fresh)) {
        await _unknown(epoch);
        return;
      }
      // Query first: an old committed/applying/unknown receipt is authoritative.
      try {
        final receipt = await api.operation(_pending!.id);
        if (_current(epoch)) await _pollReceipt(receipt, epoch);
        return;
      } on CompanionException catch (error) {
        if (error.code != 'resultUnknown') rethrow;
      }
      if (!_current(epoch) || !_active || isWriteBlocked()) return;
      await _persist('queued');
      if (!_current(epoch) || !_active || isWriteBlocked()) return;
      final receipt = await api.submit(_pending!.wire);
      if (_current(epoch)) await _pollReceipt(receipt, epoch);
    } catch (_) {
      if (_current(epoch)) await _unknown(epoch);
    } finally {
      _working = false;
    }
  }

  Future<void> acceptCurrentAfterReboot() async {
    if (!_alive || _working || !state.rebootNeedsConfirmation || !_hasPending) {
      return;
    }
    final epoch = _epoch;
    final fresh = await api.state();
    if (!_current(epoch)) return;
    if (fresh.bootId == _pendingBoot) return;
    await _persist('abandoned');
    await repository.saveBaseline(fresh.instanceId, fresh.wire);
    if (!_current(epoch)) return;
    _pending = null;
    _uploadPending = null;
    _base = fresh;
    _local = null;
    _set(state.copyWith(
        snapshot: fresh,
        rebootNeedsConfirmation: false,
        hasPreparedLoad: false,
        merge: null,
        operationStatus: SyncOperationStatus.draft,
        message: '已保留机身当前配置；装卷需重新选择并确认'));
  }
}
