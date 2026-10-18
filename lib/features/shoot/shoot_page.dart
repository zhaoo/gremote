import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_presence.dart';
import '../../app/theme/app_colors.dart';
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
        backgroundColor: GRemoteColors.night,
        body: SafeArea(
          bottom: false,
          child: Stack(children: [
            Column(children: [
              ShootTopBar(
                exposureMode: camera.value(ParamKey.exposureMode) ?? 'GR III',
                onBack: _goHome,
                onRecipe: () => setState(() => _showRecipes = !_showRecipes),
                onTimer: () => _cycleTimer(camera),
                onHistogram: _toggleHistogram,
                onSettings: () => _showSettings(camera),
                histogram: _histogram,
                recipeDetached: recipeSession.detached,
              ),
              if (_showRecipes)
                RecipeStrip(
                  recipes: recipes,
                  session: recipeSession,
                  onSelect: _activateRecipe,
                  onAdd: () => _addRecipe(camera),
                ),
              if (recipeSession.detached)
                Container(
                  width: double.infinity,
                  color: const Color(0xAA682C25),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: const Text('已脱离',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10)),
                ),
              Expanded(
                child: _mode == ShootMode.more
                    ? MoreGrid(
                        onProbe: () => unawaited(_exitTo('/probe', push: true)))
                    : LayoutBuilder(builder: (context, constraints) {
                        final height = constraints.maxHeight;
                        final width =
                            (height * 3 / 4).clamp(0.0, constraints.maxWidth);
                        return Center(
                          child: SizedBox(
                            width: width,
                            height: (width * 4 / 3).clamp(0.0, height),
                            child: ShootViewfinder(
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
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ),
                                    ),
                                  ),
                              ]),
                            ),
                          ),
                        );
                      }),
              ),
              if (_mode == ShootMode.pro)
                CameraParamRow(
                  state: camera,
                  onSelected: (param) => setState(() => _ruler = param),
                )
              else if (_mode == ShootMode.photo)
                _AspectDots(camera: camera)
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

  void _cycleTimer(CameraState camera) {
    final drive = camera.param(ParamKey.drive);
    if (drive?.writable != true) return;
    const values = ['single', 'self2s', 'self10s'];
    final current = values.indexOf(drive!.current ?? '');
    final next = values[(current + 1) % values.length];
    if (drive.options.contains(next)) {
      unawaited(ref
          .read(cameraStateControllerProvider.notifier)
          .setParam(drive.wireKey, next));
    }
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
      backgroundColor: GRemoteColors.navy,
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

  void _showSettings(CameraState camera) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GRemoteColors.navy,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(18),
          children: [
            Text('更多参数', style: Theme.of(context).textTheme.titleLarge),
            for (final param in camera.params.values.where((param) => !{
                  'av',
                  'tv',
                  'sv',
                  'xv',
                  'WBMode',
                  'meteringMode',
                  'aspectRatio',
                  'exposureMode'
                }.contains(param.wireKey)))
              ListTile(
                title: Text(shootParamLabel(param.wireKey)),
                trailing: Text(shootValueLabel(param.wireKey, param.current)),
                onTap: param.writable
                    ? () {
                        Navigator.pop(context);
                        setState(() => _ruler = param);
                      }
                    : null,
              ),
            const SwitchListTile(
              value: false,
              onChanged: null,
              title: Text('测光渐变延时（实验）'),
              subtitle: Text('真机温度门禁通过后开放'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AspectDots extends StatelessWidget {
  const _AspectDots({required this.camera});

  final CameraState camera;

  @override
  Widget build(BuildContext context) {
    final aspect = camera.param(ParamKey.aspectRatio);
    if (aspect == null) return const SizedBox(height: 26);
    return SizedBox(
      height: 26,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final value in aspect.options)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: GestureDetector(
              key: Key('aspect-$value'),
              onTap: aspect.writable
                  ? () => unawaited(ProviderScope.containerOf(context)
                      .read(cameraStateControllerProvider.notifier)
                      .setParam(aspect.wireKey, value))
                  : null,
              child: Container(
                width: value == aspect.current ? 8 : 5,
                height: value == aspect.current ? 8 : 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value == aspect.current
                      ? GRemoteColors.gold
                      : GRemoteColors.muted,
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
