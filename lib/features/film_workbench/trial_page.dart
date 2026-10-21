import 'dart:async';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../camera/live/live_view_controller.dart';
import '../../film/catalog/film_catalog.dart';
import '../../film/export/recipe_card_codec.dart';
import '../../film/model/film_recipe.dart';
import '../../film/preview/film_preview_controller.dart';
import '../../imaging/imaging_engine.dart';
import 'rolls_page.dart';
import 'workbench_providers.dart';
import 'widgets/comparison_preview.dart';
import 'widgets/film_picker.dart';
import 'widgets/texture_sheet.dart';
import 'widgets/workbench_style.dart';

class TrialPage extends ConsumerStatefulWidget {
  const TrialPage(
      {super.key,
      required this.onStartRoll,
      required this.onLoadCamera,
      this.active = true});
  final VoidCallback onStartRoll, onLoadCamera;
  final bool active;
  @override
  ConsumerState<TrialPage> createState() => _TrialPageState();
}

class _TrialPageState extends ConsumerState<TrialPage>
    with WidgetsBindingObserver {
  late final FilmPreviewController _preview;
  PreviewImage? _source;
  String _sourceLabel = '示例照片 · AI 生成', _sourceError = '';
  bool _processed = false, _reapply = false, _live = false, _decoding = false;
  int _sourceGeneration = 0;
  Uint8List? _pendingJpeg;
  Timer? _liveTimer;
  LiveViewController? _liveController;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _preview = FilmPreviewController(ref.read(filmPreviewEngineProvider))
      ..addListener(_changed);
    unawaited(_sample());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _sample() async {
    final generation = ++_sourceGeneration;
    try {
      final catalog = await ref.read(filmCatalogProvider.future);
      if (!mounted || generation != _sourceGeneration) return;
      final source = await ref.read(trialSampleLoaderProvider)();
      if (!mounted || generation != _sourceGeneration) return;
      ref.read(selectedFilmRecipeProvider.notifier).state ??=
          catalog.recipe(33);
      setState(() => _source = source);
      _render();
    } catch (error) {
      if (mounted && generation == _sourceGeneration) {
        setState(() => _sourceError = '示例暂不可用，可选择自己的照片');
      }
    }
  }

  void _render() {
    final recipe = ref.read(selectedFilmRecipeProvider);
    if (_source != null && recipe != null) {
      _preview.request(
          source: _source!,
          recipe: recipe,
          alreadyProcessed: _processed && !_reapply);
    }
  }

  void _choose(FilmCatalog catalog, FilmDefinition film) {
    ref.read(selectedFilmRecipeProvider.notifier).state =
        catalog.recipe(film.id);
    _render();
  }

  void _stopLive() {
    _liveTimer?.cancel();
    _liveTimer = null;
    _pendingJpeg = null;
    if (_live) {
      _liveController?.detach();
      _live = false;
    }
  }

  @override
  void didUpdateWidget(covariant TrialPage old) {
    super.didUpdateWidget(old);
    if (!widget.active) _stopLive();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stopLive();
  }

  Future<void> _liveInput() async {
    _stopLive();
    ++_sourceGeneration;
    _liveController = ref.read(liveViewControllerProvider.notifier);
    _liveController!.attach();
    setState(() {
      _live = true;
      _processed = true;
      _reapply = false;
      _sourceLabel = '实时取景 · 已含机内色彩';
      _sourceError = '';
    });
    _liveTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (!mounted || !_live || _preview.busy) return;
      final bytes = ref.read(liveViewControllerProvider);
      if (bytes != null) {
        unawaited(_accept(bytes));
      } else if (mounted) {
        setState(
            () => _sourceError = _liveController?.error ?? '等待相机取景画面，请确认相机已连接');
      }
    });
  }

  Future<void> _accept(Uint8List bytes) async {
    _pendingJpeg = bytes;
    if (_decoding) return;
    _decoding = true;
    try {
      while (_pendingJpeg != null && mounted) {
        final current = _pendingJpeg!, generation = _sourceGeneration;
        _pendingJpeg = null;
        try {
          final source =
              await ref.read(trialImageDecoderProvider).decode(current);
          if (!mounted || generation != _sourceGeneration) continue;
          setState(() {
            _source = source;
            _sourceError = '';
          });
          _render();
        } catch (error) {
          if (mounted && generation == _sourceGeneration) {
            setState(() => _sourceError = '无法读取这张照片，请选择 JPEG');
          }
        }
      }
    } finally {
      _decoding = false;
    }
  }

  Future<void> _input() async {
    final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        sheetAnimationStyle: workbenchSheetAnimation(context),
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('选择 JPEG 照片'),
                  onTap: () => Navigator.pop(context, 'jpeg')),
              ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('使用实时取景'),
                  subtitle: const Text('默认保留机内色彩，可明确选择重新试色'),
                  onTap: () => Navigator.pop(context, 'live')),
              ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('导入配方卡'),
                  onTap: () => Navigator.pop(context, 'recipe')),
            ])));
    if (!mounted || choice == null) return;
    try {
      if (choice == 'live') {
        await _liveInput();
        return;
      }
      final file = await openFile(acceptedTypeGroups: [
        choice == 'recipe'
            ? const XTypeGroup(
                label: '配方卡',
                extensions: ['json'],
                mimeTypes: ['application/json'],
                uniformTypeIdentifiers: ['public.json'])
            : const XTypeGroup(
                label: 'JPEG',
                extensions: ['jpg', 'jpeg'],
                mimeTypes: ['image/jpeg'],
                uniformTypeIdentifiers: ['public.jpeg'])
      ]);
      if (file == null || !mounted) return;
      final limit = choice == 'recipe' ? 16384 : 20 * 1024 * 1024;
      if (await file.length() > limit) throw const FormatException('文件过大');
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (choice == 'recipe') {
        final recipe = RecipeCardCodec.decode(bytes),
            catalog = await ref.read(filmCatalogProvider.future);
        if (recipe.catalogHash != catalog.hash ||
            recipe.rendererHash != catalog.rendererHash) {
          throw const FormatException('配方卡需要不同版本的胶卷目录，当前无法预览');
        }
        catalog.film(recipe.filmId);
        if (!mounted) return;
        ref.read(selectedFilmRecipeProvider.notifier).state = recipe;
        _render();
      } else {
        _stopLive();
        ++_sourceGeneration;
        setState(() {
          _processed = true;
          _reapply = false;
          _sourceLabel = '本地 JPEG · 默认保留原色';
        });
        await _accept(bytes);
      }
    } catch (error) {
      if (mounted) setState(() => _sourceError = '$error');
    }
  }

  Future<void> _start(FilmRecipe recipe) async {
    final roll = await showCreateRollSheet(
        context, ref.read(filmRepositoryProvider), recipe);
    if (roll != null && mounted) {
      ref.read(filmRollRevisionProvider.notifier).state++;
      widget.onStartRoll();
    }
  }

  @override
  void dispose() {
    _sourceGeneration++;
    _stopLive();
    WidgetsBinding.instance.removeObserver(this);
    _preview.removeListener(_changed);
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(filmCatalogProvider);
    return catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('胶卷目录加载失败：$error')),
        data: (catalog) {
          final recipe =
                  ref.watch(selectedFilmRecipeProvider) ?? catalog.recipe(33),
              film = catalog.film(recipe.filmId);
          return ListView(key: const PageStorageKey('film-trial'), children: [
            const WorkbenchHeading('试卷台', '找到这一刻的颜色。', 'YOUR FILMS. YOUR GR.'),
            ComparisonPreview(
                original: _source,
                effect:
                    _preview.result?.recipeFingerprint == recipe.fingerprint &&
                            _preview.result?.generation == _preview.generation
                        ? _preview.result?.image
                        : null,
                effectName: film.name),
            Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 12, 0),
                child: Row(children: [
                  Expanded(
                      child: Text(_sourceLabel,
                          style: const TextStyle(
                              fontSize: 10, color: workbenchMuted))),
                  TextButton(
                      onPressed: _input,
                      child:
                          const Text('切换照片 ↗', style: TextStyle(fontSize: 11)))
                ])),
            if (_sourceError.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Text(_sourceError,
                      style:
                          const TextStyle(color: workbenchGold, fontSize: 12))),
            if (_processed)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: SwitchListTile.adaptive(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      title: const Text('重新试色', style: TextStyle(fontSize: 13)),
                      subtitle: const Text('已处理 JPEG 可能重复叠色',
                          style: TextStyle(fontSize: 11)),
                      value: _reapply,
                      onChanged: (value) {
                        setState(() => _reapply = value);
                        _render();
                      })),
            Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 12, 4),
                child: Row(children: [
                  const Expanded(
                      child: Text('为今天选一卷',
                          style: TextStyle(
                              color: workbenchCream,
                              fontWeight: FontWeight.w600))),
                  TextButton(
                      onPressed: () async {
                        final chosen = await showFilmPicker(context, catalog);
                        if (chosen != null && mounted) _choose(catalog, chosen);
                      },
                      child: Text('全部 ${catalog.entries.length} 卷',
                          style: const TextStyle(fontSize: 11)))
                ])),
            FilmPicker(
                films: catalog.entries,
                selectedId: film.id,
                onSelect: (film) => _choose(catalog, film)),
            Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 12, 8),
                child: Column(children: [
                  const Divider(color: Color(0xff303d31)),
                  Row(children: [
                    Expanded(
                        child: Text(
                            '颗粒 ${recipe.parameters['grain'] ?? 0}  /  光晕 ${recipe.parameters['haloGain'] ?? 0}',
                            style: const TextStyle(
                                color: workbenchCream, fontSize: 11))),
                    TextButton(
                        onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            sheetAnimationStyle:
                                workbenchSheetAnimation(context),
                            builder: (_) => TextureSheet(
                                film: film,
                                recipe: recipe,
                                onChanged: (parameters) {
                                  ref
                                          .read(selectedFilmRecipeProvider.notifier)
                                          .state =
                                      catalog.recipe(film.id,
                                          name: recipe.name,
                                          parameters: parameters);
                                  _render();
                                })),
                        child:
                            const Text('调整质感', style: TextStyle(fontSize: 11)))
                  ]),
                ])),
            if (_preview.error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Text('预览暂不可用：${_preview.error}',
                      style:
                          const TextStyle(color: workbenchGold, fontSize: 11))),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 22),
                child: Text('近似预览 · 与机内最终 JPEG 会有差异',
                    style: TextStyle(color: workbenchMuted, fontSize: 10))),
            Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  OutlinedButton(
                      onPressed: widget.onLoadCamera,
                      child: const Text('装入相机')),
                  FilledButton(
                      onPressed: () => _start(recipe),
                      child: const Text('用这卷开始'))
                ])),
          ]);
        });
  }
}
