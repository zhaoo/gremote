import 'dart:async';
import '../../camera/companion/camera_film_catalog.dart';
import '../../film/store/sync_repository.dart';
import '../../darkroom/darkroom_providers.dart';
import 'widgets/film_picker.dart';
import 'widgets/texture_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_presence.dart';
import '../../app/widgets/workspace_motion.dart';
import '../../camera/companion/companion_protocol.dart';
import '../../camera/companion/companion_sync_controller.dart';
import '../../camera/companion/film_transfer.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../../camera/companion/sync_state.dart';
import '../../camera/companion/three_way_merge.dart';
import '../../film/catalog/film_catalog.dart';
import '../../film/model/film_recipe.dart';
import 'companion_providers.dart';
import 'workbench_providers.dart';
import 'widgets/workbench_style.dart';

class CameraFilmsPage extends ConsumerStatefulWidget {
  const CameraFilmsPage({super.key, this.active = true, this.initialFilmId});
  final bool active;
  final int? initialFilmId;
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
      _scheduled = false,
      _preparing = false;
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
              !_preparing &&
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
      final recipes = <FilmRecipe>[
        ...await SyncRepository(ref.read(databaseProvider)).cameraRecipes(),
        ...await ref.read(filmRepositoryProvider).savedRecipes()
      ];
      if (!mounted) return;
      final selected = await showModalBottomSheet<FilmRecipe>(
          context: context,
          sheetAnimationStyle: _filmSheetAnimation(context),
          builder: (context) => SafeArea(
              child: recipes.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('还没有本地配方。开卷或保留冲突配方后会出现在这里。',
                          style: TextStyle(color: context.palette.muted)))
                  : ListView.builder(
                      itemCount: recipes.length,
                      itemBuilder: (context, index) {
                        final recipe = recipes[index];
                        return ListTile(
                            title: Text(
                                recipe.name.isEmpty
                                    ? '配方 ${recipe.filmId}'
                                    : recipe.name,
                                style: TextStyle(color: context.palette.text)),
                            subtitle: Text(_parameters(recipe.parameters),
                                style: TextStyle(
                                    color: context.palette.muted,
                                    fontSize: 11)),
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

  void _useCameraRecipe(
      CompanionSnapshot snapshot, CameraFilmCatalog? catalog) {
    try {
      final id = snapshot.slots[_slot]['filmId'] as int;
      final name = catalog?.film(id).name ?? '相机胶卷';
      final recipe = snapshot.recipeAt(_slot, name: name);
      setState(() {
        _saved = recipe;
        _imported = null;
      });
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _adjustCamera(
      CameraFilmCatalog catalog, CameraFilmRecipe recipe) async {
    if (_preparing) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        sheetAnimationStyle: _filmSheetAnimation(context),
        builder: (_) => TextureSheet(
            film: catalog.film(recipe.filmId),
            recipe: recipe,
            readOnlyParameters: (cameraContract['readOnlyParameters'] as List)
                .cast<String>()
                .toSet(),
            onChanged: (parameters) {
              if (mounted) {
                setState(() => _saved = catalog.recipe(recipe.filmId,
                    name: recipe.name, parameters: parameters));
              }
            }));
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
    if (_preparing) return;
    final requestedSlot = _slot, activate = _activate, film = _imported;
    setState(() => _preparing = true);
    try {
      await controller.prepareLoad(
          slot: requestedSlot, recipe: recipe, activate: activate, film: film);
      if (!mounted) return;
      final prepared = controller.preparedLoad;
      if (prepared == null) throw const FormatException('装卷准备已失效，请重新选择并确认');
      setState(() => _slot = prepared.slot);
      await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          sheetAnimationStyle: _filmSheetAnimation(context),
          builder: (context) => _LoadSheet(
              catalog: ref.read(cameraFilmCatalogProvider).valueOrNull ??
                  ref.read(filmCatalogProvider).valueOrNull,
              controller: controller,
              preparedLoad: prepared));
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _more(CompanionSyncController? controller, FilmCatalog? catalog,
      {required String connectionMessage,
      required bool usingSavedPairing}) async {
    final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        sheetAnimationStyle: _filmSheetAnimation(context),
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              ListTile(
                  title: const Text('胶卷与数据'),
                  subtitle: Text(connectionMessage)),
              ListTile(
                  leading: const Icon(Icons.collections_bookmark_outlined),
                  title: const Text('相机目录'),
                  enabled: catalog != null,
                  onTap: catalog == null
                      ? null
                      : () => Navigator.pop(context, 'catalog')),
              ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: const Text('导入胶卷数据'),
                  enabled: catalog != null &&
                      !_picking &&
                      controller?.state.capabilities?.supports('uploadFilm') ==
                          true,
                  onTap: catalog != null &&
                          !_picking &&
                          controller?.state.capabilities
                                  ?.supports('uploadFilm') ==
                              true
                      ? () => Navigator.pop(context, 'import')
                      : null),
              ListTile(
                  leading: const Icon(Icons.bookmark_outline),
                  title: const Text('本地配方'),
                  onTap: () => Navigator.pop(context, 'saved')),
              if (controller?.state.snapshot != null &&
                  controller!.state.snapshot!.slots[_slot]['filmId'] != 0)
                ListTile(
                    title: const Text('使用机身配方'),
                    onTap: () => Navigator.pop(context, 'camera')),
              if (_imported != null || _saved != null)
                ListTile(
                    title: const Text('恢复所选胶卷'),
                    onTap: () => Navigator.pop(context, 'reset')),
              if (usingSavedPairing) ...[
                const Divider(),
                ListTile(
                    leading: const Icon(Icons.link_off_outlined),
                    title: const Text('移除旧版配对'),
                    enabled: !_picking,
                    onTap: _picking
                        ? null
                        : () => Navigator.pop(context, 'unpair')),
              ],
            ])));
    if (!mounted) return;
    switch (action) {
      case 'catalog':
        if (catalog == null) return;
        final film = await showFilmPicker(context, catalog);
        if (film != null && mounted) {
          setState(() {
            _saved = catalog.recipe(film.id);
            _imported = null;
          });
        }
      case 'import':
        if (catalog != null) await _import(catalog);
      case 'saved':
        await _chooseSaved();
      case 'camera':
        if (controller?.state.snapshot != null) {
          _useCameraRecipe(controller!.state.snapshot!,
              catalog is CameraFilmCatalog ? catalog : null);
        }
      case 'reset':
        setState(() {
          _imported = null;
          _saved = null;
        });
      case 'unpair':
        await _removePairing();
    }
  }

  Future<void> _retry(CompanionSyncController controller) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('重试原操作？'),
                content: const Text(
                    '将再次核对机身状态，并使用原操作编号和相同配置重试。不会重复创建装卷操作，也不会继续未确认的切换。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('以原操作重试'))
                ]));
    if (confirmed == true && mounted) await controller.retryOriginalOperation();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(companionIdentityHydrationProvider);
    final controller = ref.watch(companionSyncControllerProvider),
        cameraCatalog = ref.watch(cameraFilmCatalogProvider).valueOrNull,
        identity = ref.watch(effectiveCompanionIdentityProvider);
    final connected = ref.watch(connectionControllerProvider
        .select((connection) => connection is ConnectionReady));
    final discovery = ref.watch(companionHotspotPairingProvider);
    final saved = ref.watch(companionPairingIdentityProvider);
    final usingSavedPairing = saved != null && identical(saved, identity);
    final discovering = connected &&
        (discovery.isLoading || (identity != null && controller == null));
    final fallbackMessage = !connected
        ? '连接相机 Wi-Fi 后，GRemote 会自动连接 M10V。'
        : discovering
            ? '正在自动连接 M10V…'
            : '未检测到 M10V 服务。请确认已开启 GRemote 连接，并安装配套 SD 脚本。';
    final FilmCatalog? catalog =
        cameraCatalog ?? ref.watch(filmCatalogProvider).valueOrNull;
    _configure(controller, ref.watch(companionNetworkReadyProvider),
        ref.watch(appForegroundProvider));
    final selected = _imported != null && catalog != null
        ? _imported!.recipe(catalog.hash)
        : _saved ??
            (widget.initialFilmId != null && catalog != null
                ? catalog.recipe(widget.initialFilmId!)
                : ref.watch(selectedFilmRecipeProvider));
    Widget content() {
      final state = controller?.state, snapshot = state?.snapshot;
      final connectionMessage =
          state?.connectionStatus == SyncConnectionStatus.busy
              ? '相机正忙，请稍后写入'
              : state?.connectionStatus == SyncConnectionStatus.connecting
                  ? '正在读取机身配置'
                  : state?.message ?? fallbackMessage;
      final canPrepare = controller != null &&
          state != null &&
          !state.readOnly &&
          !state.pending &&
          !state.stale &&
          state.connectionStatus == SyncConnectionStatus.ready &&
          snapshot != null &&
          !snapshot.busy &&
          selected != null &&
          !_picking &&
          !_preparing;
      return Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(
                  child: Text(
                      snapshot == null
                          ? connected
                              ? 'M10V 机内胶卷'
                              : '相机未连接'
                          : state!.readOnly
                              ? '机身配置 · 只读'
                              : '机身 · ${snapshot.slots.length} 槽',
                      style: TextStyle(
                          color: context.palette.muted, fontSize: 12))),
              IconButton(
                  tooltip: controller == null ? '重试 M10V 连接' : '读取机身配置',
                  onPressed: _picking
                      ? null
                      : controller != null
                          ? () => unawaited(controller.refresh())
                          : connected && !discovering
                              ? () => ref
                                  .invalidate(companionHotspotPairingProvider)
                              : null,
                  icon: Icon(Icons.refresh,
                      color: context.palette.muted, size: 20)),
              IconButton(
                  tooltip: '更多胶卷操作',
                  onPressed: _preparing
                      ? null
                      : () => _more(controller, catalog,
                          connectionMessage: connectionMessage,
                          usingSavedPairing: usingSavedPairing),
                  icon: Icon(Icons.more_horiz, color: context.palette.muted)),
            ])),
        Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
              if (snapshot == null ||
                  state!.readOnly ||
                  state.stale ||
                  state.pending ||
                  (state.operationStatus != SyncOperationStatus.draft &&
                      state.operationStatus != SyncOperationStatus.synced) ||
                  state.connectionStatus != SyncConnectionStatus.ready)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(connectionMessage,
                        style: TextStyle(
                            color: context.palette.muted, height: 1.5))),
              if (state?.stale == true && snapshot != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('上次读取的配置，当前状态待核对',
                        style: TextStyle(color: context.palette.muted))),
              if (state?.pending == true)
                Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                        onPressed: () =>
                            unawaited(controller!.reconcileUnknown()),
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: const Text('核对结果'))),
              if (state?.canRetryOriginal == true)
                Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                        onPressed: () => _retry(controller!),
                        child: const Text('重试原操作'))),
              if (state?.rebootNeedsConfirmation == true)
                Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                        onPressed: () =>
                            unawaited(controller!.acceptCurrentAfterReboot()),
                        child: const Text('保留机身当前配置'))),
              if (snapshot != null)
                for (var i = 0; i < snapshot.slots.length; i++)
                  _slotCard(i, snapshot, catalog),
            ])),
        Container(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
            decoration: BoxDecoration(
                border:
                    Border(top: BorderSide(color: context.palette.divider))),
            child: SafeArea(
                top: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    _filmIcon(context, _definition(catalog, selected?.filmId),
                        size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(
                            selected == null
                                ? '选择胶卷'
                                : selected.name.isEmpty
                                    ? '配方 ${selected.filmId}'
                                    : selected.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.palette.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w600))),
                    if (cameraCatalog != null && selected is CameraFilmRecipe)
                      TextButton(
                          onPressed: _preparing
                              ? null
                              : () => _adjustCamera(cameraCatalog, selected),
                          child: Text('调整参数',
                              style: TextStyle(
                                  color: context.palette.muted, fontSize: 12))),
                  ]),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('写入后使用',
                          style: TextStyle(
                              color: context.palette.text, fontSize: 14)),
                      value: _activate,
                      onChanged: state?.pending == true || _preparing
                          ? null
                          : (value) {
                              if (_preparing) return;
                              setState(() => _activate = value);
                            }),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: context.palette.accent,
                              foregroundColor: context.palette.onAccent,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14)),
                          onPressed: canPrepare
                              ? () => _prepare(controller, selected)
                              : null,
                          child: Text(
                              '写入槽位 ${(_slot + 1).toString().padLeft(2, '0')}'))),
                ]))),
      ]);
    }

    return controller == null
        ? content()
        : ListenableBuilder(
            listenable: controller, builder: (context, child) => content());
  }

  Widget _slotCard(int slot, CompanionSnapshot snapshot, FilmCatalog? catalog) {
    final id = snapshot.slots[slot]['filmId'] as int;
    final film = _definition(catalog, id);
    final name = _filmName(catalog, id);
    return Material(
        color: slot == _slot ? context.palette.raised : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            key: ValueKey('camera-film-slot-$slot'),
            onTap: _preparing ? null : () => setState(() => _slot = slot),
            child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: context.palette.divider, width: .5))),
                child: Row(children: [
                  SizedBox(
                      width: 24,
                      child: Text((slot + 1).toString().padLeft(2, '0'),
                          style: TextStyle(
                              color: context.palette.muted, fontSize: 11))),
                  _filmIcon(context, film, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(name,
                          style: TextStyle(
                              color: id == 0
                                  ? context.palette.muted
                                  : context.palette.text,
                              fontSize: 13))),
                  if (snapshot.activeSlot == slot)
                    Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text('机内使用中',
                            style: TextStyle(
                                color: context.palette.muted, fontSize: 10))),
                  if (_slot == slot)
                    Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(Icons.check,
                            size: 17, color: context.palette.text)),
                ]))));
  }
}

AnimationStyle _filmSheetAnimation(BuildContext context) {
  final duration = WorkspaceMotion.duration(context, 280);
  return duration == Duration.zero
      ? AnimationStyle.noAnimation
      : AnimationStyle(
          duration: duration,
          reverseDuration: WorkspaceMotion.duration(context, 200));
}

FilmDefinition? _definition(FilmCatalog? catalog, int? id) {
  for (final entry in catalog?.entries ?? <FilmDefinition>[]) {
    if (entry.id == id) return entry;
  }
  return null;
}

String _filmName(FilmCatalog? catalog, int id) => id == 0
    ? '空槽'
    : _definition(catalog, id)?.name ??
        (id >= 79 && id <= 288 ? '自定义胶卷 $id' : '配方 $id');

Widget _filmIcon(BuildContext context, FilmDefinition? film,
        {required double size}) =>
    film == null
        ? SizedBox(
            width: size,
            height: size,
            child:
                Icon(Icons.crop_square, color: context.palette.muted, size: 18))
        : Image.asset(film.icon,
            width: size, height: size, fit: BoxFit.contain);

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
      {required this.controller, this.catalog, required this.preparedLoad});
  final CompanionSyncController controller;
  final FilmCatalog? catalog;
  final PreparedCompanionLoad preparedLoad;
  @override
  State<_LoadSheet> createState() => _LoadSheetState();
}

class _LoadSheetState extends State<_LoadSheet> {
  final choices = <String, ConflictChoice>{};
  bool _resolving = false, _details = false;
  bool _matchesPreparation(PreparedCompanionLoad? load) =>
      load != null &&
      load.slot == widget.preparedLoad.slot &&
      identical(load.recipe, widget.preparedLoad.recipe) &&
      (load.activate == widget.preparedLoad.activate ||
          widget.controller.state.merge?.keepLocalSlots.contains(load.slot) ==
              true);

  void _confirm() {
    if (!_matchesPreparation(widget.controller.preparedLoad)) return;
    unawaited(widget.controller.confirm());
  }

  Future<void> _resolve() async {
    if (_resolving || !_matchesPreparation(widget.controller.preparedLoad)) {
      return;
    }
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
        final currentLoad = widget.controller.preparedLoad;
        final samePreparation = _matchesPreparation(currentLoad);
        // Keep the finished intent visible for its receipt, but never confirm a
        // cached intent after the controller prepares a different operation.
        final load = currentLoad ?? widget.preparedLoad;
        final slot = load.slot, recipe = load.recipe;

        final targetId = state.snapshot?.slots[slot]['filmId'] as int? ?? 0;
        final keepLocal = state.merge?.keepLocalSlots.contains(slot) == true;
        final canConfirm = samePreparation &&
            !state.pending &&
            !state.readOnly &&
            !state.stale &&
            state.snapshot?.busy == false &&
            state.connectionStatus == SyncConnectionStatus.ready &&
            state.hasPreparedLoad &&
            state.merge?.readOnly == false &&
            state.merge?.resolved == true &&
            !_resolving &&
            state.operationStatus != SyncOperationStatus.synced;
        final parameters = state.merge == null
            ? recipe.parameters
            : wireMap(wireMap(
                (state.merge!.merged['slots'] as List)[slot])['parameters']);
        return SafeArea(
            child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .9),
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('确认装卷',
                              style: TextStyle(
                                  color: context.palette.text,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 16),
                          Flexible(
                              child: SingleChildScrollView(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                Row(children: [
                                  _filmIcon(
                                      context,
                                      _definition(
                                          widget.catalog, recipe.filmId),
                                      size: 52),
                                  const SizedBox(width: 16),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(
                                            recipe.name.isEmpty
                                                ? _filmName(widget.catalog,
                                                    recipe.filmId)
                                                : recipe.name,
                                            style: TextStyle(
                                                color: context.palette.text,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 6),
                                        Text(
                                            keepLocal
                                                ? '手机配方单独保留，机内槽位不变'
                                                : load.activate
                                                    ? '写入后使用'
                                                    : '写入后不切换当前胶卷',
                                            style: TextStyle(
                                                color: context.palette.muted,
                                                fontSize: 12)),
                                      ])),
                                ]),
                                const SizedBox(height: 20),
                                Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                        color: context.palette.raised,
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        spacing: 12,
                                        runSpacing: 6,
                                        children: [
                                          Text('目标槽位',
                                              style: TextStyle(
                                                  color: context.palette.muted,
                                                  fontSize: 12)),
                                          Text(
                                              '${(slot + 1).toString().padLeft(2, '0')} · ${_filmName(widget.catalog, targetId)}',
                                              style: TextStyle(
                                                  color: context.palette.text,
                                                  fontSize: 12)),
                                        ])),
                                if (targetId != 0 &&
                                    !keepLocal &&
                                    state.operationStatus !=
                                        SyncOperationStatus.synced)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Text(
                                          '将覆盖：${_filmName(widget.catalog, targetId)}',
                                          style: TextStyle(
                                              color: context.palette.text,
                                              fontSize: 13))),
                                if (currentLoad != null && !samePreparation)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Text('准备内容已变化，请返回后重新确认',
                                          style: TextStyle(
                                              color: context.palette.text))),
                                if (state.operationStatus !=
                                        SyncOperationStatus.draft ||
                                    state.readOnly ||
                                    state.stale)
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      child: Text(state.message,
                                          style: TextStyle(
                                              color: context.palette.text,
                                              height: 1.5))),
                                // Conflicts remain visible even when optional parameter details are folded.
                                for (final conflict in state.merge?.conflicts ??
                                    <SyncConflict>[])
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(_fieldLabel(conflict.path),
                                                style: TextStyle(
                                                    color:
                                                        context.palette.text)),
                                            const SizedBox(height: 8),
                                            Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: [
                                                  for (final option
                                                      in ConflictChoice.values)
                                                    ChoiceChip(
                                                        label: Text(
                                                            switch (option) {
                                                          ConflictChoice
                                                                .local =>
                                                            '手机 ${conflict.local}',
                                                          ConflictChoice
                                                                .remote =>
                                                            '机身 ${conflict.remote}',
                                                          ConflictChoice
                                                                .keepBoth =>
                                                            '保留两份'
                                                        }),
                                                        selected: choices[
                                                                conflict
                                                                    .path] ==
                                                            option,
                                                        onSelected: state
                                                                    .pending ||
                                                                _resolving
                                                            ? null
                                                            : (_) => setState(() =>
                                                                choices[conflict
                                                                        .path] =
                                                                    option)),
                                                ]),
                                          ])),
                                if ((state.merge?.conflicts.isNotEmpty ??
                                        false) &&
                                    !(state.merge?.resolved ?? true))
                                  OutlinedButton(
                                      onPressed: _resolving || state.pending
                                          ? null
                                          : _resolve,
                                      child: const Text('保存冲突选择')),
                                TextButton.icon(
                                    onPressed: () =>
                                        setState(() => _details = !_details),
                                    style: TextButton.styleFrom(
                                        foregroundColor: context.palette.muted,
                                        padding: EdgeInsets.zero),
                                    iconAlignment: IconAlignment.end,
                                    icon: Icon(
                                        _details
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        size: 16),
                                    label: const Text('参数明细',
                                        style: TextStyle(fontSize: 12))),
                                WorkspaceReveal(
                                    visible: _details,
                                    child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(_parameters(parameters),
                                                  style: TextStyle(
                                                      color:
                                                          context.palette.muted,
                                                      fontSize: 12,
                                                      height: 1.6)),
                                              if (state.merge != null)
                                                for (final change in _changes(
                                                    state.snapshot?.config,
                                                    state.merge!.merged,
                                                    catalog: widget.catalog))
                                                  Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 8),
                                                      child: Text(change,
                                                          style: TextStyle(
                                                              color: context
                                                                  .palette
                                                                  .muted,
                                                              fontSize: 12))),
                                            ]))),
                                if ({
                                  SyncOperationStatus.queued,
                                  SyncOperationStatus.applying,
                                  SyncOperationStatus.verifying
                                }.contains(state.operationStatus))
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      child: LinearProgressIndicator(
                                          minHeight: 3,
                                          color: context.palette.muted)),
                              ]))),
                          const SizedBox(height: 12),
                          SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: context.palette.accent,
                                      foregroundColor: context.palette.onAccent,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14)),
                                  onPressed: canConfirm ? _confirm : null,
                                  child: Text(state.operationStatus ==
                                          SyncOperationStatus.synced
                                      ? '已核对完成'
                                      : '确认写入'))),
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('返回')),
                        ]))));
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

List<String> _changes(Map<String, Object?>? before, Map<String, Object?> after,
    {FilmCatalog? catalog}) {
  if (before == null) return [];
  final rows = <String>[];
  final a = before['slots'] as List, b = after['slots'] as List;
  for (var i = 0; i < b.length; i++) {
    final old = wireMap(a[i]), next = wireMap(b[i]);
    if (old['filmId'] != next['filmId']) {
      String name(Object? id) {
        for (final entry in catalog?.entries ?? <FilmDefinition>[]) {
          if (entry.id == id) return entry.name;
        }
        return '配方 $id';
      }

      rows.add(
          '槽位 ${(i + 1).toString().padLeft(2, '0')}：${name(old['filmId'])} → ${name(next['filmId'])}');
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
