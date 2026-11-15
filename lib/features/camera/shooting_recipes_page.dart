import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../camera/companion/companion_protocol.dart';
import '../../camera/companion/companion_sync_controller.dart';
import '../../camera/companion/extensions_protocol.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../../camera/recipe/shooting_recipe.dart';
import '../../camera/sync/camera_state_controller.dart';
import '../../darkroom/darkroom_providers.dart';
import '../../diagnostics/diagnostic_event.dart';
import '../../diagnostics/diagnostic_store.dart';
import '../../film/model/film_recipe.dart';
import '../film_workbench/companion_providers.dart';
import '../shoot/shoot_labels.dart';
import 'extensions_providers.dart';

class ShootingRecipesPage extends ConsumerStatefulWidget {
  const ShootingRecipesPage(
      {super.key,
      this.filmId,
      this.recordedRecipe,
      this.recordedExposure,
      this.applyOnOpen = false});
  final int? filmId;
  final ShootingRecipe? recordedRecipe;
  final RecordedExposure? recordedExposure;
  final bool applyOnOpen;

  @override
  ConsumerState<ShootingRecipesPage> createState() =>
      _ShootingRecipesPageState();
}

class _ShootingRecipesPageState extends ConsumerState<ShootingRecipesPage> {
  late final _store = ShootingRecipeStore(ref.read(databaseProvider));
  late var _recipes = _store.list();
  var _working = false;
  final _clock = Stopwatch()..start();
  String? _message;
  Future<void> Function()? _undo;

  @override
  void initState() {
    super.initState();
    final recipe = widget.recordedRecipe;
    if (widget.applyOnOpen &&
        (recipe != null || widget.recordedExposure != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final sync = ref.read(companionSyncControllerProvider);
        if (sync != null) {
          _run(() async {
            final exposure = widget.recordedExposure;
            if (exposure == null) return _apply(sync, recipe!);
            sync.setActive(true);
            final snapshot = await _refresh(sync);
            if (!mounted) return;
            final bodyRecipe = exposure.resolve(
                ref.read(cameraStateControllerProvider),
                snapshot,
                sync.contract);
            await _apply(sync, bodyRecipe, fromBody: true);
          });
        }
      });
    }
  }

  ShootingRecipe _snapshot(
      CompanionSnapshot snapshot, String name, Map<String, int> effects) {
    final camera = ref.read(cameraStateControllerProvider);
    return ShootingRecipe.fromCamera(name, snapshot, camera, effects) ??
        (throw StateError('请先在机内选择一款胶卷'));
  }

  Future<Map<String, int>> _readEffects() async {
    final extensions = ref.read(cameraExtensionsControllerProvider);
    if (extensions == null) return const {};
    await extensions.refresh();
    final snapshot = extensions.snapshot;
    if (!extensions.canWrite || snapshot == null) {
      throw StateError('请等待相机扩展设置就绪');
    }
    return {
      for (final key in recipeEffectKeys)
        if (snapshot.values[key] case final int value) key: value,
    };
  }

  Future<void> _writeEffects(Map<String, int> target, Map<String, int> allowed,
      bool Function() sameSession) async {
    for (final key in recipeEffectKeys) {
      final value = target[key];
      if (value == null) continue;
      final extensions = ref.read(cameraExtensionsControllerProvider);
      if (!sameSession() || extensions == null) {
        throw StateError('请重新连接相机');
      }
      await extensions.refresh();
      final snapshot = extensions.snapshot;
      if (!sameSession() ||
          !extensions.canWrite ||
          snapshot == null ||
          !snapshot.supported.contains(key)) {
        throw StateError('当前机身无法应用配方效果');
      }
      if (snapshot.values[key] == value) continue;
      if (snapshot.values[key] != allowed[key]) {
        throw StateError('机身效果已变化，请重新确认');
      }
      await extensions.set(key, value, expectedRevision: snapshot.revision);
      if (!sameSession() ||
          extensions.pending ||
          extensions.snapshot?.values[key] != value) {
        throw StateError('效果结果待核对');
      }
    }
  }

  Future<CompanionSnapshot> _refresh(CompanionSyncController sync) async {
    final stateController = ref.read(cameraStateControllerProvider.notifier);
    await stateController.refresh();
    await sync.refresh();
    final snapshot = sync.state.snapshot;
    if (!mounted ||
        snapshot == null ||
        !snapshot.fresh ||
        snapshot.busy ||
        sync.state.readOnly ||
        sync.state.stale ||
        sync.state.pending ||
        sync.isWriteBlocked()) {
      throw StateError('请连接 M10V 并等待机身空闲');
    }
    return snapshot;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    final log = ref.read(diagnosticStoreProvider);
    final start = _clock.elapsedMicroseconds;
    String? outcome;
    try {
      await action();
    } catch (error) {
      outcome = 'readbackOrConnection';
      if (mounted) {
        setState(() =>
            _message = error is StateError ? error.message : '操作未完成，请核对机身后重试');
      }
    } finally {
      log.record(DiagnosticEvent(
          stage: 'shootingRecipe',
          monotonicMicros: start,
          durationMs: (_clock.elapsedMicroseconds - start) ~/ 1000,
          retryCount: 0,
          exceptionCode: outcome));
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save(CompanionSyncController sync) async {
    var name = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('保存当前配方'),
        content: TextField(
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(labelText: '配方名称'),
          onChanged: (value) => name = value.trim(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (confirmed != true || name.isEmpty || !mounted) return;
    final snapshot = await _refresh(sync);
    final effects = await _readEffects();
    if (!mounted) return;
    await _store.save(_snapshot(snapshot, name, effects));
    if (mounted) {
      setState(() {
        _recipes = _store.list();
        _message = '已保存';
      });
    }
  }

  Future<void> _apply(CompanionSyncController sync, ShootingRecipe recipe,
      {bool fromBody = false}) async {
    sync.setActive(true);
    final starting = await _refresh(sync);
    if (!mounted) return;
    if (recipe.catalog != sync.catalogHash ||
        recipe.renderer != sync.rendererHash) {
      throw StateError('胶卷版本不匹配');
    }
    final originalSlot = starting.activeSlot;
    if (originalSlot == null) throw StateError('请先选择机内胶卷');
    final slot = starting.slots.indexWhere((value) =>
        value['filmId'] == recipe.film['filmId'] &&
        value['customHash'] == recipe.film['customHash']);
    if (slot < 0) throw StateError('请先将配方使用的胶卷装入相机');
    final originalFilm = starting.slots[slot];
    final originalEffects = await _readEffects();
    if (!mounted) return;
    final original = _snapshot(starting, '应用前', originalEffects);
    final modeChanges = recipe.settings['WBMode'] != null &&
        recipe.settings['WBMode'] != original.settings['WBMode'];
    if (!recipe.effects.keys.every((key) =>
        originalEffects.containsKey(key) ||
        (modeChanges &&
            key == 'wbKelvin' &&
            originalEffects.containsKey('wbGreenMagenta')))) {
      throw StateError('当前机身缺少配方使用的效果');
    }
    final defaultSettings = Map.of(recipe.settings)
      ..removeWhere((key, _) => exposureRecipeKeys.contains(key));
    final fromPhoto = fromBody || identical(recipe, widget.recordedRecipe);
    var includeExposure = fromPhoto;
    final confirmed = fromPhoto ||
        (await showDialog<bool>(
              context: context,
              builder: (dialog) => StatefulBuilder(builder: (context, update) {
                final selected =
                    includeExposure ? recipe.settings : defaultSettings;
                return AlertDialog(
                  title: Text('应用「${recipe.name}」'),
                  content: SingleChildScrollView(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('胶卷槽位 ${originalSlot + 1} → ${slot + 1}'),
                      if (canonicalJson(originalFilm) !=
                          canonicalJson(recipe.film))
                        const Text('恢复该胶卷的逐卷设置'),
                      for (final MapEntry(:key, :value)
                          in recipe.effects.entries)
                        if (original.effects[key] != value &&
                            key != 'filmTexture')
                          Text(
                              '${extensionFields[key]!.label}：${extensionFields[key]!.choices?[value] ?? value}'),
                      for (final MapEntry(:key, :value) in selected.entries)
                        if (original.settings[key] != value)
                          Text(
                              '${shootParamLabel(key)}：${shootValueLabel(key, original.settings[key])} → ${shootValueLabel(key, value)}'),
                      if (recipe.settings.keys.any(exposureRecipeKeys.contains))
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('同时应用曝光参数'),
                          value: includeExposure,
                          onChanged: (value) =>
                              update(() => includeExposure = value ?? false),
                        ),
                    ],
                  )),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: const Text('应用')),
                  ],
                );
              }),
            )) ==
            true;
    if (!confirmed || !mounted) return;
    final controller = ref.read(cameraStateControllerProvider.notifier);
    final generation = controller.sessionGeneration;
    final current = await _refresh(sync);
    final currentEffects = await _readEffects();
    if (!mounted) return;
    final now = _snapshot(current, '应用前', currentEffects);
    if (current.bootId != starting.bootId ||
        current.revision != starting.revision ||
        current.activeSlot != originalSlot ||
        canonicalJson(original.settings) != canonicalJson(now.settings) ||
        canonicalJson(originalEffects) != canonicalJson(currentEffects)) {
      throw StateError('机身设置已变化，请重新确认');
    }
    bool sameSession() =>
        mounted &&
        controller.sessionGeneration == generation &&
        ref.read(connectionControllerProvider) is ConnectionReady &&
        !sync.isWriteBlocked();
    if (!sameSession()) throw StateError('相机连接已变化');
    final changes = recipeChanges(ref.read(cameraStateControllerProvider),
        includeExposure ? recipe.settings : defaultSettings);
    final rollback = {
      for (final key in changes.keys) key: original.settings[key]!
    };
    final wb = Map.of(recipe.effects)
      ..removeWhere((key, _) => !whiteBalanceExtensionKeys.contains(key));
    final otherEffects = Map.of(recipe.effects)
      ..removeWhere((key, _) => whiteBalanceExtensionKeys.contains(key));
    final texture = otherEffects.remove('filmTexture');
    int? previousTexture;
    bool sameFilm(Map<String, Object?> current, Map<String, Object?> wanted) {
      if (texture == null) {
        return canonicalJson(current) == canonicalJson(wanted);
      }
      Map<String, Object?> withoutTexture(Map<String, Object?> film) {
        final parameters = wireMap(film['parameters'])
          ..removeWhere((key, _) =>
              (sync.contract['readOnlyParameters'] as List? ?? [])
                  .contains(key));
        return {...film, 'parameters': parameters};
      }

      return canonicalJson(withoutTexture(current)) ==
          canonicalJson(withoutTexture(wanted));
    }

    Map<String, int>? previousTargetWhiteBalance;
    Future<void> undo() async {
      if (!sameSession()) throw StateError('请核对机身');
      final fresh = await _refresh(sync);
      if (fresh.bootId != current.bootId ||
          fresh.instanceId != current.instanceId ||
          (fresh.activeSlot != slot && fresh.activeSlot != originalSlot) ||
          (!sameFilm(fresh.slots[slot], recipe.film) &&
              !sameFilm(fresh.slots[slot], originalFilm)) ||
          (originalSlot != slot &&
              canonicalJson(fresh.slots[originalSlot]) !=
                  canonicalJson(original.film))) {
        throw StateError('机身设置已变化，请核对机身');
      }
      final state = ref.read(cameraStateControllerProvider);
      final effects = await _readEffects();
      if (!sameSession()) throw StateError('相机连接已变化');
      for (final key in otherEffects.keys) {
        if (effects[key] != recipe.effects[key] &&
            effects[key] != originalEffects[key]) {
          throw StateError('机身效果已变化，请核对机身');
        }
      }
      for (final key in changes.keys) {
        final value = state.params[key]?.current;
        if (value != changes[key] && value != rollback[key]) {
          throw StateError('机身设置已变化，请核对机身');
        }
      }
      if (previousTargetWhiteBalance case final previous?) {
        if (state.params['WBMode']?.current != recipe.settings['WBMode'] &&
            modeChanges) {
          throw StateError('白平衡模式已变化，请核对机身');
        }
        for (final key in previous.keys) {
          if (effects[key] != wb[key] && effects[key] != previous[key]) {
            throw StateError('白平衡已变化，请核对机身');
          }
        }
        await _writeEffects(previous, wb, sameSession);
      }
      if (previousTexture case final prior?) {
        if (fresh.activeSlot != slot ||
            (effects['filmTexture'] != texture &&
                effects['filmTexture'] != prior)) {
          throw StateError('机身逐卷效果已变化，请核对机身');
        }
        await _writeEffects(
            {'filmTexture': prior}, {'filmTexture': texture!}, sameSession);
      }
      final restore = recipeChanges(state, rollback);
      await writeRecipeSettings(restore, controller.setParam, sameSession);
      await _writeEffects({
        for (final key in otherEffects.keys) key: originalEffects[key]!,
      }, otherEffects, sameSession);
      final undoBase = await _refresh(sync);
      if (undoBase.bootId != fresh.bootId ||
          undoBase.activeSlot != fresh.activeSlot ||
          !sameFilm(undoBase.slots[slot], fresh.slots[slot])) {
        throw StateError('机身胶卷已变化，请核对机身');
      }
      if (!await sync.restoreRecipeSlot(undoBase, slot, originalFilm)) {
        throw StateError('胶卷恢复结果待核对');
      }
      if (originalSlot != slot &&
          !await sync.restoreRecipeSlot(
              await _refresh(sync), originalSlot, original.film)) {
        throw StateError('机身确认结果待核对');
      }
      if (mounted) {
        setState(() {
          _undo = null;
          _message = '已恢复应用前的设置';
        });
      }
    }

    setState(() => _undo = undo);
    if (!await sync.restoreRecipeSlot(current, slot, recipe.film,
            restoreTextureSeparately: texture != null) ||
        !sameSession()) {
      throw StateError('胶卷状态待核对');
    }
    if (texture != null) {
      final activeEffects = await _readEffects();
      previousTexture = activeEffects['filmTexture'];
      if (previousTexture == null) throw StateError('当前胶卷的逐卷效果不可用');
      await _writeEffects({'filmTexture': texture}, activeEffects, sameSession);
    }
    await writeRecipeSettings(changes, controller.setParam, sameSession);
    if (wb.isNotEmpty) {
      final target = await _readEffects();
      if (!wb.keys.every(target.containsKey)) {
        throw StateError('机身白平衡模式无法恢复照片中的偏移或色温');
      }
      previousTargetWhiteBalance = {
        for (final key in wb.keys) key: target[key]!
      };
      await _writeEffects(wb, previousTargetWhiteBalance, sameSession);
    }
    await _writeEffects(otherEffects, originalEffects, sameSession);
    final applied = await _refresh(sync);
    final appliedEffects = await _readEffects();
    if (!sameSession() ||
        applied.activeSlot != slot ||
        canonicalJson(applied.slots[slot]) != canonicalJson(recipe.film) ||
        recipe.effects.entries
            .any((item) => appliedEffects[item.key] != item.value) ||
        changes.entries.any((item) =>
            ref.read(cameraStateControllerProvider).params[item.key]?.current !=
            item.value)) {
      throw StateError('应用完成后的机身状态待核对');
    }
    if (mounted) setState(() => _message = '已应用，相机已确认');
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(companionSyncControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('拍摄配方')),
      body: SafeArea(
          child: FutureBuilder(
        future: _recipes,
        builder: (context, data) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.recordedRecipe case final ShootingRecipe recipe)
              FilledButton(
                onPressed: _working || sync == null
                    ? null
                    : () => _run(() => _apply(sync, recipe)),
                child: const Text('应用手机记录的拍摄配方'),
              ),
            if (widget.filmId != null) const Text('按照片胶卷查找已存配方。请选择要应用的配方。'),
            FilledButton(
              onPressed: _working || sync == null
                  ? null
                  : () => _run(() => _save(sync)),
              child: const Text('保存当前配方'),
            ),
            if (sync == null) const Text('连接 M10V 后可保存及应用配方'),
            if (_message case final String message) Text(message),
            if (_undo case final undo?)
              TextButton(
                  onPressed: _working ? null : () => _run(undo),
                  child: const Text('撤销上次应用')),
            if (_working || data.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(),
            for (final recipe in (data.data ?? const <ShootingRecipe>[]).where(
                (recipe) =>
                    widget.filmId == null ||
                    recipe.film['filmId'] == widget.filmId))
              ListTile(
                title: Text(recipe.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: _working || sync == null
                    ? null
                    : () => _run(() => _apply(sync, recipe)),
              ),
          ],
        ),
      )),
    );
  }
}
