import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_presence.dart';
import '../../camera/companion/companion_protocol.dart';
import '../../camera/companion/companion_sync_controller.dart';
import '../../camera/companion/film_transfer.dart';
import '../../camera/companion/pairing_store.dart';
import '../../camera/companion/sync_state.dart';
import '../../camera/companion/three_way_merge.dart';
import '../../film/catalog/film_catalog.dart';
import '../../film/model/film_recipe.dart';
import 'companion_providers.dart';
import 'workbench_providers.dart';
import 'widgets/workbench_style.dart';

class CameraFilmsPage extends ConsumerStatefulWidget {
  const CameraFilmsPage({super.key, this.active = true});
  final bool active;
  @override
  ConsumerState<CameraFilmsPage> createState() => _CameraFilmsPageState();
}

class _CameraFilmsPageState extends ConsumerState<CameraFilmsPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  CompanionSyncController? _controller;
  bool _foreground = true,
      _picking = false,
      _activate = true,
      _polling = false,
      _scheduled = false;
  int _slot = 0;
  FilmTransfer? _imported;
  FilmRecipe? _saved;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(CameraFilmsPage old) {
    super.didUpdateWidget(old);
    if (!widget.active) _stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _stop();
    } else {
      if (mounted) setState(() {});
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _polling = false;
    _controller?.setActive(false);
  }

  void _configure(
      CompanionSyncController? controller, bool ready, bool foreground) {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (!identical(controller, _controller)) {
        _stop();
        _controller = controller;
      }
      final enabled = widget.active &&
          _foreground &&
          foreground &&
          ready &&
          controller != null;
      controller?.setActive(enabled);
      if (!enabled) {
        _stop();
        return;
      }
      if (!_polling) {
        _polling = true;
        unawaited(controller.refresh());
        _timer = Timer.periodic(const Duration(seconds: 2), (_) {
          if (mounted &&
              widget.active &&
              _foreground &&
              ref.read(appForegroundProvider) &&
              ref.read(companionNetworkReadyProvider)) {
            unawaited(controller.refresh());
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error is FormatException
            ? error.message
            : companionErrorMessage(error))));
  }

  Future<void> _pair() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final bytes = await ref.read(companionFilePickerProvider)('pairing');
      if (bytes == null || !mounted) return;
      final identity =
          await importPairing(bytes, ref.read(companionPairingStoreProvider));
      if (!mounted) return;
      await ref.read(companionIdentityStorageProvider).save(identity);
      if (!mounted) return;
      ref.read(companionPairingIdentityProvider.notifier).state = identity;
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _import(FilmCatalog catalog) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final bytes = await ref.read(companionFilePickerProvider)('film');
      if (bytes == null || !mounted) return;
      final film =
          FilmTransfer.parse(bytes, expectedRenderer: catalog.rendererHash);
      setState(() {
        _imported = film;
        _saved = null;
      });
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _chooseSaved() async {
    try {
      final recipes = await ref.read(filmRepositoryProvider).savedRecipes();
      if (!mounted) return;
      final selected = await showModalBottomSheet<FilmRecipe>(
          context: context,
          backgroundColor: workbenchBackground,
          builder: (context) => SafeArea(
              child: recipes.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('还没有本地配方。开卷或保留冲突配方后会出现在这里。',
                          style: TextStyle(color: workbenchMuted)))
                  : ListView.builder(
                      itemCount: recipes.length,
                      itemBuilder: (context, index) {
                        final recipe = recipes[index];
                        return ListTile(
                            title: Text(
                                recipe.name.isEmpty
                                    ? '配方 ${recipe.filmId}'
                                    : recipe.name,
                                style: const TextStyle(color: workbenchCream)),
                            subtitle: Text(_parameters(recipe.parameters),
                                style: const TextStyle(
                                    color: workbenchMuted, fontSize: 11)),
                            onTap: () => Navigator.pop(context, recipe));
                      })));
      if (selected != null && mounted) {
        setState(() {
          _saved = selected;
          _imported = null;
        });
      }
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _removePairing() async {
    final identity = ref.read(companionPairingIdentityProvider);
    if (identity == null) return;
    try {
      await ref.read(companionPairingStoreProvider).remove(identity.instanceId);
      await ref.read(companionIdentityStorageProvider).clear();
      if (!mounted) return;
      ref.read(companionPairingIdentityProvider.notifier).state = null;
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _prepare(
      CompanionSyncController controller, FilmRecipe recipe) async {
    try {
      await controller.prepareLoad(
          slot: _slot, recipe: recipe, activate: _activate, film: _imported);
      if (!mounted) return;
      await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: workbenchBackground,
          sheetAnimationStyle: MediaQuery.of(context).disableAnimations
              ? AnimationStyle.noAnimation
              : AnimationStyle(
                  duration: const Duration(milliseconds: 280),
                  reverseDuration: const Duration(milliseconds: 200)),
          builder: (context) => _LoadSheet(
              controller: controller,
              slot: _slot,
              recipe: recipe,
              activate: _activate));
    } catch (error) {
      _error(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(companionIdentityHydrationProvider);
    final controller = ref.watch(companionSyncControllerProvider),
        catalog = ref.watch(filmCatalogProvider).valueOrNull,
        identity = ref.watch(companionPairingIdentityProvider);
    _configure(controller, ref.watch(companionNetworkReadyProvider),
        ref.watch(appForegroundProvider));
    final selected = _imported != null && catalog != null
        ? _imported!.recipe(catalog.hash)
        : _saved ?? ref.watch(selectedFilmRecipeProvider);
    Widget content() =>
        ListView(padding: const EdgeInsets.only(bottom: 28), children: [
          const WorkbenchHeading('相机胶卷', '手机选好，相机带走。', 'POCKET TO CAMERA.'),
          _panel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  const Icon(Icons.camera_alt_outlined,
                      color: workbenchGold, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(
                          controller?.state.snapshot == null
                              ? '尚未连接 M10V 胶卷桥'
                              : controller!.state.readOnly
                                  ? '机身配置 · 只读'
                                  : '机身五槽',
                          style: const TextStyle(
                              color: workbenchCream,
                              fontSize: 18,
                              fontWeight: FontWeight.w600))),
                  if (identity != null)
                    IconButton(
                        tooltip: '移除当前配对',
                        onPressed: _picking ? null : _removePairing,
                        icon: const Icon(Icons.link_off_outlined,
                            color: workbenchMuted))
                ]),
                const SizedBox(height: 12),
                Text(
                    controller?.state.message ??
                        '请连接相机 Wi-Fi 并导入配对文件。机内配置读取与写入需要相机桥确认支持。',
                    style: const TextStyle(color: workbenchMuted, height: 1.7)),
                if (controller?.state.stale == true &&
                    controller?.state.snapshot != null)
                  const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('上次读取的配置，当前状态待核对',
                          style: TextStyle(color: workbenchGold))),
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  OutlinedButton.icon(
                      onPressed: _picking ? null : _pair,
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('导入配对文件')),
                  OutlinedButton.icon(
                      onPressed: controller == null || _picking
                          ? null
                          : () => unawaited(controller.refresh()),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('读取机身配置'))
                ]),
                if (controller?.state.pending == true)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: FilledButton.icon(
                          onPressed: () =>
                              unawaited(controller!.reconcileUnknown()),
                          icon: const Icon(Icons.fact_check_outlined, size: 18),
                          label: const Text('核对结果'))),
                if (controller?.state.rebootNeedsConfirmation == true)
                  TextButton(
                      onPressed: () =>
                          unawaited(controller!.acceptCurrentAfterReboot()),
                      child: const Text('保留机身当前配置')),
              ])),
          if (controller?.state.snapshot != null) ...[
            const Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 10),
                child: Text('选择目标槽位',
                    style: TextStyle(
                        color: workbenchCream,
                        fontSize: 14,
                        fontWeight: FontWeight.w600))),
            for (var i = 0; i < 5; i++)
              _slotCard(i, controller!.state.snapshot!, catalog),
          ],
          _panel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('准备带走的配方',
                    style: TextStyle(color: workbenchMuted, fontSize: 12)),
                const SizedBox(height: 8),
                Text(
                    selected?.name.isNotEmpty == true
                        ? selected!.name
                        : selected == null
                            ? '先在试卷台选择一款胶卷'
                            : '配方 ${selected.filmId}',
                    style: const TextStyle(
                        color: workbenchCream,
                        fontSize: 20,
                        fontWeight: FontWeight.w600)),
                if (selected != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_parameters(selected.parameters),
                          style: const TextStyle(
                              color: workbenchMuted, height: 1.6))),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                      onPressed: catalog == null || _picking
                          ? null
                          : () => _import(catalog),
                      icon: const Icon(Icons.file_open_outlined, size: 18),
                      label: const Text('导入胶卷数据')),
                  TextButton(
                      onPressed: _chooseSaved, child: const Text('本地配方')),
                  if (_imported != null || _saved != null)
                    TextButton(
                        onPressed: () => setState(() {
                              _imported = null;
                              _saved = null;
                            }),
                        child: const Text('使用试卷台配方'))
                ]),
                SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('装入后使用',
                        style: TextStyle(color: workbenchCream, fontSize: 14)),
                    subtitle: const Text('保存配置后，再切换机内当前胶卷',
                        style: TextStyle(color: workbenchMuted, fontSize: 11)),
                    value: _activate,
                    onChanged: controller?.state.pending == true
                        ? null
                        : (value) => setState(() => _activate = value)),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                        onPressed: controller == null ||
                                controller.state.readOnly ||
                                controller.state.pending ||
                                selected == null ||
                                _picking
                            ? null
                            : () => _prepare(controller, selected),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: Text(
                            '装入槽位 ${(_slot + 1).toString().padLeft(2, '0')}'))),
              ])),
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Text('离线时仍可试色、开卷和整理照片。无线装卷需要匹配的相机伴侣组件；未完成真机验证的构建不会开放写入。',
                  style: TextStyle(
                      color: workbenchMuted, fontSize: 12, height: 1.7))),
        ]);
    return controller == null
        ? content()
        : ListenableBuilder(
            listenable: controller, builder: (context, child) => content());
  }

  Widget _slotCard(int slot, CompanionSnapshot snapshot, FilmCatalog? catalog) {
    final value = snapshot.slots[slot], id = value['filmId'] as int;
    FilmDefinition? film;
    for (final entry in catalog?.entries ?? <FilmDefinition>[]) {
      if (entry.id == id) {
        film = entry;
        break;
      }
    }
    final name = film?.name ?? (id >= 79 && id <= 288 ? '自定义胶卷 $id' : '配方 $id');
    return Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
        child: Material(
            color: slot == _slot ? workbenchSurface : workbenchBackground,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                    color: slot == _slot ? workbenchGold : workbenchSurface)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                key: ValueKey('camera-film-slot-$slot'),
                onTap: () => setState(() => _slot = slot),
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Text((slot + 1).toString().padLeft(2, '0'),
                          style: const TextStyle(
                              color: workbenchGold, fontSize: 13)),
                      const SizedBox(width: 14),
                      if (film != null)
                        Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child:
                                Image.asset(film.icon, width: 34, height: 34)),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(name,
                                style: const TextStyle(
                                    color: workbenchCream,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(
                                _parameters(Map<String, Object?>.from(
                                    value['parameters'] as Map)),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: workbenchMuted, fontSize: 11))
                          ])),
                      if (snapshot.activeSlot == slot)
                        const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text('机内使用中',
                                style: TextStyle(
                                    color: workbenchGold, fontSize: 10))),
                      if (_slot == slot)
                        const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.check_circle_outline,
                                size: 19, color: workbenchGold))
                    ])))));
  }
}

Widget _panel({required Widget child}) => Container(
    margin: const EdgeInsets.fromLTRB(22, 16, 22, 0),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
        color: workbenchSurface, borderRadius: BorderRadius.circular(16)),
    child: child);
String _parameters(Map<String, Object?> parameters) {
  const names = {
    'grain': '颗粒',
    'grainSize': '尺寸',
    'haloGain': '光晕',
    'haloSpread': '扩散',
    'haloThreshold': '阈值',
    'haloProfile': '模式',
    'leakGain': '漏光',
    'leakPosition': '位置',
    'leakSpread': '范围',
    'leakVariation': '变化',
    'filmExposure': '模拟曝光',
    'charmeraColor': '机身颜色'
  };
  return parameters.entries
      .map((e) => '${names[e.key] ?? '未知参数'} ${e.value}')
      .join(' · ');
}

class _LoadSheet extends StatefulWidget {
  const _LoadSheet(
      {required this.controller,
      required this.slot,
      required this.recipe,
      required this.activate});
  final CompanionSyncController controller;
  final int slot;
  final FilmRecipe recipe;
  final bool activate;
  @override
  State<_LoadSheet> createState() => _LoadSheetState();
}

class _LoadSheetState extends State<_LoadSheet> {
  final choices = <String, ConflictChoice>{};
  bool _resolving = false;
  Future<void> _resolve() async {
    if (_resolving) return;
    setState(() => _resolving = true);
    try {
      await widget.controller.resolve(choices);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(companionErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        final state = widget.controller.state;
        return SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('确认装卷',
                          style: TextStyle(
                              color: workbenchCream,
                              fontSize: 22,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Text(
                          '槽位 ${(widget.slot + 1).toString().padLeft(2, '0')} · ${widget.recipe.name}',
                          style: const TextStyle(
                              color: workbenchGold, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text(
                          state.merge?.keepLocalSlots.contains(widget.slot) ==
                                  true
                              ? '手机配方单独保留，机内槽位不变'
                              : widget.activate
                                  ? '先保存配置，再切换为当前使用的胶卷'
                                  : '只保存配置，保留机内当前使用的胶卷',
                          style: const TextStyle(
                              color: workbenchMuted, height: 1.6)),
                      Flexible(
                          child: SingleChildScrollView(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Text(state.message,
                                    style: const TextStyle(
                                        color: workbenchCream, height: 1.6))),
                            if (state.merge != null)
                              for (final change in _changes(
                                  state.snapshot?.config, state.merge!.merged))
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(change,
                                        style: const TextStyle(
                                            color: workbenchMuted,
                                            fontSize: 12))),
                            for (final conflict
                                in state.merge?.conflicts ?? <SyncConflict>[])
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(_fieldLabel(conflict.path),
                                            style: const TextStyle(
                                                color: workbenchCream)),
                                        const SizedBox(height: 8),
                                        Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              for (final option
                                                  in ConflictChoice.values)
                                                ChoiceChip(
                                                    label:
                                                        Text(switch (option) {
                                                      ConflictChoice.local =>
                                                        '手机 ${conflict.local}',
                                                      ConflictChoice.remote =>
                                                        '机身 ${conflict.remote}',
                                                      ConflictChoice.keepBoth =>
                                                        '保留两份'
                                                    }),
                                                    selected: choices[
                                                            conflict.path] ==
                                                        option,
                                                    onSelected: state.pending
                                                        ? null
                                                        : (_) => setState(() =>
                                                            choices[conflict
                                                                    .path] =
                                                                option))
                                            ])
                                      ])),
                            if ((state.merge?.conflicts.isNotEmpty ?? false) &&
                                !(state.merge?.resolved ?? true))
                              OutlinedButton(
                                  onPressed: _resolving ? null : _resolve,
                                  child: const Text('保存冲突选择')),
                            if (state.pending)
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: LinearProgressIndicator(
                                      minHeight: 3, color: workbenchGold)),
                          ]))),
                      const SizedBox(height: 16),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: state.pending ||
                                      state.readOnly ||
                                      !(state.merge?.resolved ?? false) ||
                                      state.operationStatus ==
                                          SyncOperationStatus.synced
                                  ? null
                                  : () =>
                                      unawaited(widget.controller.confirm()),
                              child: Text(state.operationStatus ==
                                      SyncOperationStatus.synced
                                  ? '已核对完成'
                                  : '确认装入'))),
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('返回')),
                    ])));
      });
}

String _fieldLabel(String path) {
  final parts = path.split('.');
  if (parts.length >= 2 && parts.first == 'slots') {
    final index = int.tryParse(parts[1]), key = parts.last;
    final label = const {'filmId': '胶卷', 'customHash': '胶卷内容'}[key] ??
        ((filmContract['parameters'] as Map)[key] as Map?)?['label'] ??
        '未知参数';
    return '槽位 ${index == null ? '' : (index + 1).toString().padLeft(2, '0')} · $label';
  }
  return '机身配置';
}

List<String> _changes(
    Map<String, Object?>? before, Map<String, Object?> after) {
  if (before == null) return [];
  final rows = <String>[];
  final a = before['slots'] as List, b = after['slots'] as List;
  for (var i = 0; i < 5; i++) {
    final old = wireMap(a[i]), next = wireMap(b[i]);
    if (old['filmId'] != next['filmId']) {
      rows.add('槽位 ${i + 1}：配方 ${old['filmId']} → ${next['filmId']}');
    }
    final oldParams = wireMap(old['parameters']);
    for (final entry in wireMap(next['parameters']).entries) {
      if (oldParams[entry.key] != entry.value) {
        rows.add(
            '${_fieldLabel('slots.$i.parameters.${entry.key}')}：${oldParams[entry.key] ?? '默认'} → ${entry.value}');
      }
    }
  }
  return rows;
}
