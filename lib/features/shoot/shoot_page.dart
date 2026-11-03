import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_presence.dart';
import '../../app/theme/app_colors.dart';
import '../../app/widgets/workspace_motion.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../../camera/live/live_frame_analyzer.dart';
import '../../camera/live/live_view_controller.dart';
import '../../camera/params/camera_param.dart';
import '../../camera/params/param_writer.dart';
import '../../camera/program/program.dart';
import '../../camera/program/program_controller.dart';
import '../../camera/program/program_runner.dart';
import '../../camera/recipe/combo_recipe.dart';
import '../../camera/recipe/recipe_session.dart';
import '../../camera/recipe/recipe_store.dart';
import '../../camera/sync/camera_state.dart';
import '../../camera/sync/camera_state_controller.dart';
import '../../darkroom/darkroom_providers.dart';
import '../../location/location_recording.dart';
import 'shoot_mode.dart';
import 'shoot_labels.dart';
import 'widgets/bottom_bar.dart';
import 'widgets/dim_overlay.dart';
import 'widgets/drive_options.dart';
import 'widgets/histogram.dart';
import 'widgets/mode_carousel.dart';
import 'widgets/more_grid.dart';
import 'widgets/param_row.dart';
import 'widgets/param_ruler.dart';
import 'widgets/program_sheet.dart';
import 'widgets/recipe_editor_dialog.dart';
import 'widgets/recipe_strip.dart';
import 'widgets/top_bar.dart';
import 'widgets/viewfinder.dart';
import 'widgets/shoot_workspace_layout.dart';

class ShootPage extends ConsumerStatefulWidget {
  const ShootPage({super.key});

  @override
  ConsumerState<ShootPage> createState() => _ShootPageState();
}

class _ShootPageState extends ConsumerState<ShootPage> {
  late final AppLifecycleListener _lifecycle;
  late final LiveViewController _liveViewController;
  late final StateController<bool> _shootVisible;
  ShootMode _mode = ShootMode.photo;
  CameraParam? _ruler;
  FrameStats? _stats;
  Timer? _histogramTimer;
  var _showRecipes = false;
  var _histogram = false;
  var _dimmed = false;
  var _attached = false;
  var _focusing = false;
  Offset? _focusPoint;
  var _focusFailed = false;
  var _shutterHeld = false;
  var _shutterEpoch = 0;
  GoRouter? _router;
  bool _leaving = false;
  bool _restoreRequired = false;
  Future<void>? _pressInFlight;
  Future<SettingsRestoreReport>? _finishing;
  late final StateController<Future<bool> Function()?> _exitHandler;
  bool _restoreDialogVisible = false;
  // Retain the active shutter gesture when controls move into the landscape rail.
  final _captureControlsKey = GlobalKey(debugLabel: 'shoot-capture-controls');

  @override
  void initState() {
    super.initState();
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    _shootVisible = ref.read(shootPageVisibleProvider.notifier);
    _exitHandler = ref.read(shootExitHandlerProvider.notifier);
    _liveViewController = ref.read(liveViewControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _exitHandler.state = _prepareExit;
      _activate();
    });
    _lifecycle = AppLifecycleListener(onStateChange: (lifecycle) {
      ref.read(appForegroundProvider.notifier).state =
          lifecycle == AppLifecycleState.resumed ||
              lifecycle == AppLifecycleState.inactive;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (identical(router, _router)) return;
    _router?.routeInformationProvider.removeListener(_routeChanged);
    _router = router;
    router.routeInformationProvider.addListener(_routeChanged);
  }

  void _routeChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_router?.routeInformationProvider.value.uri.path == '/shoot') {
        if (!_leaving) _activate();
      }
    });
  }

  void _activate() {
    if (_attached ||
        _finishing != null ||
        _router?.routeInformationProvider.value.uri.path != '/shoot') return;
    _attached = true;
    if (ref.read(connectionControllerProvider) is ConnectionReady) {
      _restoreRequired = true;
    }
    _shootVisible.state = true;
    _liveViewController.attach();
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
  }

  @override
  void dispose() {
    _router?.routeInformationProvider.removeListener(_routeChanged);
    _histogramTimer?.cancel();
    _lifecycle.dispose();
    if (_attached) {
      Future.microtask(() {
        try {
          _shootVisible.state = false;
          _liveViewController.detach();
        } on StateError {
          // The whole ProviderScope was disposed with this page.
        }
      });
    }
    unawaited(SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.portraitUp]));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(connectionControllerProvider, (_, next) {
      if (next is ConnectionReady && _attached) _restoreRequired = true;
      if (next is! ConnectionReady) {
        _shutterEpoch++;
        _shutterHeld = false;
        _focusPoint = null;
      }
    });
    ref.watch(locationRecordingProvider);
    final connection = ref.watch(connectionControllerProvider);
    final connected = connection is ConnectionReady;
    final camera = ref.watch(cameraStateControllerProvider);
    final frame = ref.watch(liveViewControllerProvider);
    final program = ref.watch(programControllerProvider);
    final recipeSession = ref.watch(recipeSessionProvider);
    final recipes = ref.watch(comboRecipesProvider).valueOrNull ?? const [];
    final programActive =
        program.phase == RunPhase.running || program.phase == RunPhase.paused;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => _goHome(),
      child: Scaffold(
        backgroundColor: context.palette.background,
        body: SafeArea(
          bottom: true,
          child: Stack(children: [
            ShootWorkspaceLayout(
                header: [
                  ShootTopBar(
                    exposureMode:
                        camera.value(ParamKey.exposureMode) ?? 'GR III',
                    onBack: _goHome,
                    onRecipe: () =>
                        setState(() => _showRecipes = !_showRecipes),
                    onSettings: _showSettings,
                    recipeDetached: recipeSession.detached,
                  ),
                  WorkspaceReveal(
                      visible: _showRecipes,
                      child: RecipeStrip(
                        recipes: recipes,
                        session: recipeSession,
                        onSelect: _activateRecipe,
                        onAdd: () => _addRecipe(camera),
                      )),
                  if (recipeSession.detached)
                    Container(
                      width: double.infinity,
                      color: const Color(0xAA682C25),
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text('已脱离',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 10, color: AppPalette.dark.text)),
                    ),
                ],
                viewfinder: _mode == ShootMode.more
                    ? MoreGrid(
                        onProbe: () => unawaited(_exitTo('/probe', push: true)))
                    : ShootViewfinder(
                        frame: frame,
                        connected: connected,
                        onConnect: _goHome,
                        focusPoint: _focusPoint,
                        focusing: _focusing,
                        focusFailed: _focusFailed,
                        onFocus: connected &&
                                !programActive &&
                                !_focusing &&
                                !_shutterHeld
                            ? (point) => unawaited(_tapAf(point: point))
                            : null,
                        overlay: Stack(children: [
                          if (_histogram) HistogramOverlay(_stats),
                          if (programActive)
                            Positioned(
                              left: 10,
                              top: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xAA000000),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  child: Text(
                                    '${program.done}/${program.total}'
                                    '${program.reason == null ? '' : ' · ${shootReasonLabel(program.reason!)}'}',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: AppPalette.dark.text),
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      ),
                controls: [
                  if (_mode == ShootMode.pro || _mode == ShootMode.photo)
                    CameraParamRow(
                      state: camera,
                      compact: _mode == ShootMode.photo,
                      onSelected: (param) => setState(() => _ruler = param),
                    )
                  else if (_mode == ShootMode.bracket ||
                      _mode == ShootMode.timelapse)
                    DriveOptions(mode: _mode, onProgram: _selectDrive),
                  if (_ruler case final CameraParam ruler)
                    ParamRuler(
                      param: camera.params[ruler.wireKey] ?? ruler,
                      onChanged: (value) => unawaited(ref
                          .read(cameraStateControllerProvider.notifier)
                          .setParam(ruler.wireKey, value)),
                      onClose: () => setState(() => _ruler = null),
                    ),
                  ModeCarousel(
                    mode: _mode,
                    locked: programActive,
                    onChanged: (mode) => setState(() {
                      _mode = mode;
                      _ruler = null;
                    }),
                  ),
                  ShootBottomBar(
                    key: _captureControlsKey,
                    connected: connected,
                    focusing: _focusing,
                    shutterHeld: _shutterHeld,
                    program: program,
                    onPressed: _pressShutter,
                    onReleased: _releaseShutter,
                    onStop: () => unawaited(
                        ref.read(programControllerProvider.notifier).abort()),
                    onPause: ref.read(programControllerProvider.notifier).pause,
                    onResume: () => unawaited(
                        ref.read(programControllerProvider.notifier).resume()),
                    onLibrary: () => unawaited(_exitTo('/library')),
                    onFocus: () => unawaited(_tapAf()),
                  ),
                ]),
            if (programActive)
              Positioned(
                right: 10,
                top: 52,
                child: IconButton.filledTonal(
                  onPressed: () => setState(() => _dimmed = true),
                  icon: const Text('☾'),
                  tooltip: '暗屏',
                ),
              ),
            if (_leaving && !_restoreDialogVisible)
              const Positioned.fill(
                  child: Stack(children: [
                ModalBarrier(dismissible: false, color: Colors.black54),
                Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在恢复相机设置…'),
                ])),
              ])),
            if (_dimmed && programActive)
              DimOverlay(
                progress: '${program.done}/${program.total} · 点击恢复显示',
                onDismiss: () => setState(() => _dimmed = false),
              ),
          ]),
        ),
      ),
    );
  }

  void _goHome() => unawaited(_exitTo('/home'));

  Future<SettingsRestoreReport> _finishSession() {
    final pending = _finishing;
    if (pending != null) return pending;
    final operation = _doFinishSession();
    _finishing = operation;
    return operation.whenComplete(() {
      if (identical(_finishing, operation)) _finishing = null;
    });
  }

  Future<SettingsRestoreReport> _doFinishSession() async {
    _attached = false;
    _shootVisible.state = false;
    _histogramTimer?.cancel();
    _histogram = false;
    _stats = null;
    _liveViewController.detach();
    await ref.read(locationRecordingProvider.notifier).sync();
    try {
      if (!_restoreRequired &&
          ref.read(connectionControllerProvider) is! ConnectionReady) {
        return const SettingsRestoreReport();
      }
      await ref.read(programControllerProvider.notifier).abort();
      await _pressInFlight?.catchError((Object _) {});
      if (_shutterHeld) await _releaseShutter();
      await ref.read(cameraGatewaysProvider).transport.stopLiveView();
      if (ref.read(connectionControllerProvider) is! ConnectionReady) {
        return !_restoreRequired
            ? const SettingsRestoreReport()
            : const SettingsRestoreReport(failed: {'connection': 'offline'});
      }
      final report = await ref
          .read(cameraStateControllerProvider.notifier)
          .restoreConnectionSettings();
      if (report.success) _restoreRequired = false;
      return report;
    } catch (_) {
      return const SettingsRestoreReport(
          failed: {'connection': 'restoreFailed'});
    } finally {
      _shutterEpoch++;
      _shutterHeld = false;
    }
  }

  Future<void> _exitTo(String destination, {bool push = false}) async {
    if (_leaving) return;
    if (push) {
      final allowed = await _prepareExit();
      if (!mounted) return;
      if (!allowed) return;
      // Imperative pushes retain /shoot in the reported URI. Keep the route
      // listener from reactivating its session underneath the pushed page.
      setState(() => _leaving = true);
      try {
        await context.push(destination);
      } finally {
        if (mounted) {
          setState(() => _leaving = false);
          _activate();
        }
      }
    } else {
      context.go(destination);
    }
  }

  Future<bool> _prepareExit() async {
    if (!mounted) return true;
    if (_leaving) return false;
    setState(() => _leaving = true);
    var leave = true;
    try {
      var report = await _finishSession();
      while (mounted && !report.success) {
        setState(() => _restoreDialogVisible = true);
        if (!mounted) return true;
        final decision = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
                    title: const Text('部分机内参数未恢复'),
                    content: Text(
                        '${report.failed.keys.map((key) => key == 'connection' ? '相机连接' : shootParamLabel(key)).join('、')}。请确认相机保持连接后重试。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext, 'stay'),
                          child: const Text('留在拍摄')),
                      TextButton(
                          onPressed: () =>
                              Navigator.pop(dialogContext, 'leave'),
                          child: const Text('仍然退出')),
                      FilledButton(
                          onPressed: () =>
                              Navigator.pop(dialogContext, 'retry'),
                          child: const Text('重试恢复')),
                    ]));
        if (mounted) setState(() => _restoreDialogVisible = false);
        if (decision == 'retry') {
          report = await _finishSession();
        } else {
          leave = decision == 'leave';
          break;
        }
      }
      if (!mounted) return true;
      if (leave) {
        unawaited(SystemChrome.setPreferredOrientations(
            const [DeviceOrientation.portraitUp]));
      }
      return leave;
    } finally {
      if (mounted) {
        setState(() => _leaving = false);
        if (!leave) _activate();
      }
    }
  }

  Future<void> _pressShutter() async {
    if (_focusing || _shutterHeld) return;
    final epoch = _shutterEpoch;
    setState(() => _shutterHeld = true);
    try {
      final operation =
          ref.read(connectionControllerProvider.notifier).pressShutter();
      _pressInFlight = operation;
      await operation;
      _pressInFlight = null;
    } catch (_) {
      if (mounted && epoch == _shutterEpoch) {
        setState(() => _shutterHeld = false);
        _feedback('拍摄请求失败，请检查相机连接');
      }
      rethrow;
    } finally {
      _pressInFlight = null;
    }
  }

  Future<void> _releaseShutter() async {
    if (!_shutterHeld) return;
    final epoch = _shutterEpoch;
    try {
      await ref.read(connectionControllerProvider.notifier).releaseShutter();
      if (mounted &&
          epoch == _shutterEpoch &&
          ref.read(connectionControllerProvider) is ConnectionReady) {
        unawaited(
            ref.read(cameraStateControllerProvider.notifier).trackAppShot());
      }
    } finally {
      if (mounted && epoch == _shutterEpoch) {
        setState(() => _shutterHeld = false);
      }
    }
  }

  Future<void> _tapAf({Offset point = const Offset(.5, .5)}) async {
    final program = ref.read(programControllerProvider);
    if (program.phase == RunPhase.running || program.phase == RunPhase.paused) {
      return;
    }
    if (_focusing ||
        _shutterHeld ||
        ref.read(connectionControllerProvider) is! ConnectionReady) return;
    setState(() {
      _focusing = true;
      _focusFailed = false;
      _focusPoint = point;
    });
    try {
      await ref
          .read(connectionControllerProvider.notifier)
          .focus(x: (point.dx * 100).round(), y: (point.dy * 100).round());
    } catch (_) {
      if (mounted) {
        setState(() => _focusFailed = true);
        _feedback('对焦请求失败，相机可能不支持或已断开连接');
      }
    } finally {
      if (mounted) setState(() => _focusing = false);
    }
  }

  void _feedback(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleHistogram() {
    setState(() => _histogram = !_histogram);
    _histogramTimer?.cancel();
    if (!_histogram) return;
    _histogramTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      final frame = ref.read(liveViewControllerProvider);
      if (frame == null) return;
      final stats = await ref.read(liveFrameAnalyzerProvider).analyze(frame);
      if (mounted) setState(() => _stats = stats);
    });
  }

  Future<double?> _meter() async {
    final frame = ref.read(liveViewControllerProvider);
    if (frame == null) return null;
    return (await ref.read(liveFrameAnalyzerProvider).analyze(frame))?.meanLuma;
  }

  Future<void> _activateRecipe(ComboRecipe recipe) async {
    final outcome =
        await ref.read(recipeSessionProvider.notifier).activate(recipe);
    if (!mounted) return;
    if (outcome is WriteRejected || outcome is WritesDisabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('相机未接受这个机内配方')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(recipe.name), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _addRecipe(CameraState camera) async {
    final effects = camera.param(ParamKey.effect)?.options ?? const <String>[];
    if (effects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('相机未报告机内配方')),
      );
      return;
    }
    final presets = await ref.read(darkroomStoreProvider).presets();
    if (!mounted) return;
    final recipe = await showDialog<ComboRecipe>(
      context: context,
      builder: (_) => RecipeEditorDialog(
        effects: effects,
        presets: presets,
        store: ref.read(recipeStoreProvider),
      ),
    );
    if (recipe != null) {
      ref.invalidate(comboRecipesProvider);
      setState(() {});
    }
  }

  Future<void> _selectDrive(String kind) async {
    if (kind.startsWith('native')) {
      final value = kind == 'nativeBracket' ? 'bracket' : 'interval';
      unawaited(ref
          .read(cameraStateControllerProvider.notifier)
          .setParam(ParamKey.drive.wireKey, value));
      return;
    }
    final camera = ref.read(cameraStateControllerProvider);
    final recipes = await ref.read(recipeStoreProvider).recipes();
    if (!mounted) return;
    final program = await showModalBottomSheet<Program>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProgramSheet(
        kind: kind,
        camera: camera,
        recipes: recipes,
        meter: _meter,
      ),
    );
    if (program != null) {
      unawaited(ref.read(programControllerProvider.notifier).start(program));
    }
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: AnimationStyle(
          duration: WorkspaceMotion.duration(context, 250),
          reverseDuration: WorkspaceMotion.duration(context, 200)),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) => Consumer(builder: (context, ref, _) {
          final camera = ref.watch(cameraStateControllerProvider);
          final extras = camera.params.values.where((param) =>
              hasShootParamLabel(param.wireKey) &&
              !{
                'av',
                'tv',
                'sv',
                'xv',
                'WBMode',
                'meteringMode',
                'aspectRatio',
                'exposureMode',
                'stillFormat',
                'focusSetting',
                'focusMode'
              }.contains(param.wireKey));
          Widget parameter(CameraParam param) => _SettingsRow(
                label: shootParamLabel(param.wireKey),
                value: shootValueLabel(param.wireKey, param.current),
                onTap: _canSet(camera, param)
                    ? () {
                        Navigator.pop(sheetContext);
                        setState(() => _ruler = param);
                      }
                    : null,
              );
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: Container(
                            width: 30,
                            height: 3,
                            decoration: BoxDecoration(
                                color: context.palette.muted,
                                borderRadius: BorderRadius.circular(3)))),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: Text('拍摄设置',
                              style: Theme.of(context).textTheme.titleLarge)),
                      IconButton(
                          tooltip: '关闭拍摄设置',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close, size: 20)),
                    ]),
                    const _SettingsGroupLabel('拍摄'),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('直方图'),
                        trailing: Switch(
                            key: const Key('settings-histogram'),
                            value: _histogram,
                            activeTrackColor: context.palette.muted,
                            activeColor: context.palette.accent,
                            onChanged: (_) => updateSheet(_toggleHistogram))),
                    Divider(height: 1, color: context.palette.divider),
                    _SettingsRow(
                        label: '定时拍摄',
                        value: _timerLabel(camera.value(ParamKey.drive)),
                        onTap: _canSet(camera, camera.param(ParamKey.drive))
                            ? () => _showTimerChoices(context)
                            : null),
                    const _SettingsGroupLabel('相机'),
                    for (final key in [
                      'stillFormat',
                      'focusSetting',
                      'focusMode'
                    ])
                      if (camera.params[key] case final CameraParam param)
                        parameter(param),
                    const _AspectChoices(),
                    if (extras.isNotEmpty)
                      ExpansionTile(
                        key: const Key('settings-more-parameters'),
                        expansionAnimationStyle: AnimationStyle(
                            duration: WorkspaceMotion.duration(context, 200)),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title:
                            const Text('更多参数', style: TextStyle(fontSize: 14)),
                        children: [
                          for (final param in extras) parameter(param)
                        ],
                      ),
                    Divider(height: 1, color: context.palette.divider),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            const Icon(Icons.local_movies_outlined, size: 28),
                        title: const Text('机内胶卷'),
                        subtitle: Text('选择胶卷与装卷',
                            style: TextStyle(
                                fontSize: 11, color: context.palette.muted)),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          unawaited(_exitTo('/camera'));
                        }),
                  ]),
            ),
          );
        }),
      ),
    );
  }

  bool _canSet(CameraState camera, CameraParam? param) =>
      camera.online &&
      camera.writesEnabled &&
      param?.writable == true &&
      !camera.pending.containsKey(param!.wireKey);

  String _timerLabel(String? value) => switch (value) {
        null || 'single' => '关闭',
        'self2s' => '2 秒',
        'self10s' => '10 秒',
        _ => shootValueLabel('shootMode', value),
      };

  void _showTimerChoices(BuildContext settingsContext) {
    showModalBottomSheet<void>(
      context: settingsContext,
      sheetAnimationStyle: AnimationStyle(
          duration: WorkspaceMotion.duration(context, 250),
          reverseDuration: WorkspaceMotion.duration(context, 200)),
      isScrollControlled: true,
      constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(settingsContext).height * .85),
      builder: (context) => Consumer(builder: (context, ref, _) {
        final camera = ref.watch(cameraStateControllerProvider);
        final drive = camera.param(ParamKey.drive);
        return SafeArea(
            child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Expanded(
                  child: Text('定时拍摄', style: TextStyle(fontSize: 18))),
              IconButton(
                  tooltip: '关闭定时选择',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20)),
            ]),
            for (final (wire, label) in [
              ('single', '关闭'),
              ('self2s', '2 秒'),
              ('self10s', '10 秒')
            ])
              ListTile(
                  key: Key('timer-$wire'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(label),
                  trailing: drive?.current == wire
                      ? const Icon(Icons.check, size: 20)
                      : null,
                  selected: drive?.current == wire,
                  onTap: _canSet(camera, drive) && drive!.options.contains(wire)
                      ? () {
                          if (wire != drive.current) {
                            unawaited(ref
                                .read(cameraStateControllerProvider.notifier)
                                .setParam(drive.wireKey, wire));
                          }
                          Navigator.pop(context);
                        }
                      : null),
          ]),
        ));
      }),
    );
  }
}

class _AspectChoices extends ConsumerWidget {
  const _AspectChoices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final camera = ref.watch(cameraStateControllerProvider);
    final aspect = camera.param(ParamKey.aspectRatio);
    if (aspect == null) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('画幅',
              style: TextStyle(fontSize: 12, color: context.palette.muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final value in aspect.options)
              ChoiceChip(
                  key: Key('aspect-$value'),
                  label: Text(shootValueLabel(aspect.wireKey, value)),
                  showCheckmark: false,
                  selected: value == aspect.current,
                  onSelected: camera.online &&
                          camera.writesEnabled &&
                          aspect.writable &&
                          !camera.pending.containsKey(aspect.wireKey)
                      ? (_) {
                          if (value != aspect.current) {
                            unawaited(ref
                                .read(cameraStateControllerProvider.notifier)
                                .setParam(aspect.wireKey, value));
                          }
                        }
                      : null),
          ]),
        ]));
  }
}

class _SettingsGroupLabel extends StatelessWidget {
  const _SettingsGroupLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 4),
        child: Text(label,
            style: TextStyle(fontSize: 11, color: context.palette.muted)),
      );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.value, this.onTap});
  final String label, value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Column(children: [
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label, style: const TextStyle(fontSize: 14)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * .42),
                  child: Text(value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12, color: context.palette.muted))),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right,
                    size: 17, color: context.palette.muted)
              ],
            ]),
            onTap: onTap),
        Divider(height: 1, color: context.palette.divider),
      ]);
}
