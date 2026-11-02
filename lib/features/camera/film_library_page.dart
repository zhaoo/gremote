import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../app/theme/app_colors.dart';
import '../../app/widgets/workspace_motion.dart';
import 'camera_availability.dart';
import 'widgets/film_library_tile.dart';
import '../../camera/companion/camera_film_catalog.dart';
import '../../film/catalog/official_film_library.dart';
import '../../film/preview/film_preview_engine.dart';
import '../../imaging/imaging_engine.dart';
import '../darkroom/darkroom_controller.dart';
import '../film_workbench/camera_films_page.dart';
import '../film_workbench/companion_providers.dart';
import '../film_workbench/workbench_providers.dart';
import '../film_workbench/widgets/comparison_preview.dart';

final officialFilmLibraryProvider = Provider((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return OfficialFilmLibrary(
      client: client, directory: getApplicationSupportDirectory);
});
final officialFilmCacheProvider = FutureProvider((ref) async {
  try {
    final catalog = await ref.watch(cameraFilmCatalogProvider.future);
    return await ref
        .watch(officialFilmLibraryProvider)
        .cached(expectedRenderer: catalog.rendererHash);
  } catch (_) {
    return null;
  }
});

class FilmLibraryPage extends ConsumerStatefulWidget {
  const FilmLibraryPage({super.key});
  @override
  ConsumerState<FilmLibraryPage> createState() => _FilmLibraryPageState();
}

class _FilmLibraryPageState extends ConsumerState<FilmLibraryPage> {
  String _query = '', _group = '全部';
  bool _syncing = false, _importing = false, _searching = false;
  final _searchFocus = FocusNode();
  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  String? _error;
  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final catalog = await ref.read(cameraFilmCatalogProvider.future);
      await ref
          .read(officialFilmLibraryProvider)
          .sync(expectedRenderer: catalog.rendererHash);
      ref.invalidate(officialFilmCacheProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('胶卷库已同步')));
      }
    } catch (error) {
      final reason = switch (error) {
        SocketException() => '无法连接官网，请检查网络',
        TimeoutException() => '连接超时，请重试',
        HttpException() => error.message,
        FormatException() => error.message,
        _ => '同步失败，请重试',
      };
      if (mounted) setState(() => _error = '$reason · 已保留本地胶卷库');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final lut = await ref.read(darkroomActionsProvider).importLut();
      if (lut != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('LUT 已导入，可在照片编辑中使用；当前机身不支持无线导入 LUT')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(cameraFilmCatalogProvider);
    final cache = ref.watch(officialFilmCacheProvider).valueOrNull;
    final compatible = cache?.cameraCompatible ?? true;
    final local = catalog.valueOrNull;
    final availability = ref.watch(cameraAvailabilityProvider);
    final films = cache?.films ??
        [
          for (final f in local?.entries ?? [])
            OfficialFilm(id: f.id, name: f.name, group: f.group, icon: f.icon)
        ];
    final imported = ref
            .watch(darkroomOverviewProvider)
            .valueOrNull
            ?.luts
            .where((l) => l.imported)
            .toList() ??
        [];
    final custom = imported
        .where((l) =>
            (_group == '全部' || _group == '我的 LUT') &&
            l.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final groups = {'全部', ...films.map((f) => f.group), '我的 LUT'};
    final visible = films
        .where((f) =>
            (_group == '全部' || f.group == _group) &&
            '${f.name} ${f.group}'.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final slot = availability.snapshot?.activeSlot;
    final filmId =
        slot == null ? null : availability.snapshot!.slots[slot]['filmId'];
    final current =
        local?.entries.where((f) => f.id == filmId).firstOrNull?.name ?? '空槽';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (availability.canReadFilms)
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
            child: Row(children: [
              const Text('机内胶卷',
                  style: TextStyle(fontSize: 12, color: GRemoteColors.muted)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      slot == null
                          ? '—'
                          : '${(slot + 1).toString().padLeft(2, '0')} · $current',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13))),
              TextButton(
                  onPressed: () => _openSlots(context),
                  child: const Text('十槽 ›')),
            ])),
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 12, 6),
          child: Row(children: [
            Expanded(
                child: PopupMenuButton<String>(
              tooltip: '胶卷来源',
              initialValue: _group,
              onSelected: (value) => setState(() => _group = value),
              itemBuilder: (_) => [
                for (final group in groups)
                  PopupMenuItem(
                      value: group, child: Text(group == '全部' ? '全部胶卷' : group))
              ],
              child: SizedBox(
                  height: 44,
                  child: Row(children: [
                    Flexible(
                        child: Text(_group == '全部' ? '全部胶卷' : _group,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14))),
                    const SizedBox(width: 6),
                    const Icon(Icons.keyboard_arrow_down, size: 17),
                  ])),
            )),
            IconButton(
                tooltip: '搜索胶卷',
                onPressed: () {
                  setState(() {
                    _searching = !_searching;
                    if (!_searching) _query = '';
                  });
                  if (_searching) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _searchFocus.requestFocus();
                    });
                  }
                },
                icon: const Icon(Icons.search, size: 20)),
            IconButton(
                tooltip: '同步胶卷库',
                onPressed: _syncing ? null : _sync,
                icon: _syncing
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync, size: 20)),
            IconButton(
                tooltip: '导入 LUT',
                onPressed: _importing ? null : _import,
                icon: const Icon(Icons.add, size: 21)),
          ])),
      WorkspaceReveal(
          visible: _searching,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
                focusNode: _searchFocus,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                    hintText: '搜索胶卷',
                    prefixIcon: const Icon(Icons.search, size: 19),
                    filled: true,
                    fillColor: GRemoteColors.raised,
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: BorderSide.none))),
          )),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(_error!,
                style: const TextStyle(
                    color: GRemoteColors.danger, fontSize: 12))),
      if (!compatible && _group != '我的 LUT')
        const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('胶卷版本与当前机身不匹配 · 可浏览',
                style: TextStyle(color: GRemoteColors.muted, fontSize: 12))),
      if (!availability.canInstallFilms && _group != '我的 LUT')
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(availability.hint,
                style:
                    const TextStyle(color: GRemoteColors.muted, fontSize: 12))),
      Expanded(
          child: catalog.isLoading && films.isEmpty && custom.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : visible.isEmpty && custom.isEmpty
                  ? Center(child: Text(catalog.hasError ? '胶卷库读取失败' : '未找到胶卷'))
                  : LayoutBuilder(builder: (context, constraints) {
                      final itemWidth = (constraints.maxWidth - 40 - 28) / 3;
                      final labelHeight =
                          MediaQuery.textScalerOf(context).scale(12) * 2.7 + 12;
                      return GridView.builder(
                        key: const PageStorageKey('film-library-grid'),
                        padding: const EdgeInsets.fromLTRB(20, 3, 20, 24),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 16,
                            mainAxisExtent: itemWidth + labelHeight),
                        itemCount: visible.length + custom.length,
                        itemBuilder: (context, index) {
                          if (index >= visible.length) {
                            final lut = custom[index - visible.length];
                            return FilmLibraryTile(
                                name: lut.name,
                                available: true,
                                image: const ColoredBox(
                                    color: GRemoteColors.raised,
                                    child: Center(
                                        child: Icon(Icons.tune_outlined,
                                            size: 34))),
                                onTap: () => _lutDetails(lut.name));
                          }
                          final film = visible[index];
                          final icon = local?.entries
                                  .where((f) => f.id == film.id)
                                  .firstOrNull
                                  ?.icon ??
                              film.icon;
                          return FilmLibraryTile(
                              name: film.name,
                              available: compatible &&
                                  availability.canInstallFilms &&
                                  (local?.entries.any((f) => f.id == film.id) ??
                                      false),
                              image: icon.startsWith('https:')
                                  ? Image.network(icon,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Icon(
                                          Icons.local_movies_outlined))
                                  : Image.asset(icon,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Icon(
                                          Icons.local_movies_outlined)),
                              onTap: () => _details(film, local,
                                  compatible: compatible));
                        },
                      );
                    })),
    ]);
  }

  void _lutDetails(String name) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    const Text('用于照片编辑；当前机身不支持无线导入 LUT。'),
                    const SizedBox(height: 24),
                    FilledButton(
                        onPressed: () {
                          Navigator.pop(sheet);
                          context.go('/library');
                        },
                        child: const Text('选择照片')),
                    TextButton(
                        onPressed: () {
                          Navigator.pop(sheet);
                          context.push('/darkroom');
                        },
                        child: const Text('管理 LUT')),
                  ]))));

  Future<void> _details(OfficialFilm film, CameraFilmCatalog? catalog,
      {required bool compatible}) async {
    final supported = catalog?.entries.any((f) => f.id == film.id) ?? false;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => Consumer(builder: (_, ref, __) {
              final availability = ref.watch(cameraAvailabilityProvider);
              final versionMatches = compatible &&
                  (ref
                          .watch(officialFilmCacheProvider)
                          .valueOrNull
                          ?.cameraCompatible ??
                      true);
              return DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: .86,
                  minChildSize: .4,
                  maxChildSize: .95,
                  builder: (_, scroll) => ListView(
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                          children: [
                            Text(film.name,
                                style:
                                    Theme.of(context).textTheme.headlineMedium),
                            const SizedBox(height: 8),
                            Text(film.group,
                                style: const TextStyle(
                                    color: GRemoteColors.muted)),
                            if (film.description.isNotEmpty)
                              Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Text(film.description)),
                            const SizedBox(height: 24),
                            _FilmReference(id: film.id, name: film.name),
                            const SizedBox(height: 12),
                            const Text('参考预览 · 机内成片以实际拍摄为准',
                                style: TextStyle(
                                    color: GRemoteColors.muted, fontSize: 12)),
                            const SizedBox(height: 24),
                            FilledButton(
                                onPressed: versionMatches &&
                                        supported &&
                                        availability.canInstallFilms
                                    ? () {
                                        if (!ref
                                                .read(
                                                    cameraAvailabilityProvider)
                                                .canInstallFilms ||
                                            !compatible ||
                                            ref
                                                    .read(
                                                        officialFilmCacheProvider)
                                                    .valueOrNull
                                                    ?.cameraCompatible ==
                                                false) return;
                                        Navigator.pop(sheet);
                                        _openSlots(context, filmId: film.id);
                                      }
                                    : null,
                                child: const Text('装入相机')),
                            if (!versionMatches ||
                                !supported ||
                                !availability.canInstallFilms)
                              Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                      !versionMatches
                                          ? '胶卷版本与当前机身不匹配'
                                          : supported
                                              ? availability.hint
                                              : '需要更新机身胶卷目录',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: GRemoteColors.muted,
                                          fontSize: 12))),
                            TextButton(
                                onPressed: () {
                                  Navigator.pop(sheet);
                                  context.push('/darkroom');
                                },
                                child: const Text('LUT 与出图方案')),
                          ]));
            }));
  }

  void _openSlots(BuildContext context, {int? filmId}) {
    final availability = ref.read(cameraAvailabilityProvider);
    if (filmId != null
        ? !availability.canInstallFilms
        : !availability.canReadFilms) return;
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('机内胶卷')),
            body: SafeArea(child: CameraFilmsPage(initialFilmId: filmId)))));
  }
}

class _FilmReference extends ConsumerStatefulWidget {
  const _FilmReference({required this.id, required this.name});
  final int id;
  final String name;
  @override
  ConsumerState<_FilmReference> createState() => _FilmReferenceState();
}

class _FilmReferenceState extends ConsumerState<_FilmReference> {
  PreviewImage? _source, _effect;
  String? _error;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final catalog = await ref.read(filmCatalogProvider.future);
      if (!catalog.entries.any((f) => f.id == widget.id)) {
        if (mounted) setState(() => _error = '此胶卷暂无本地预览');
        return;
      }
      final source = await ref.read(trialSampleLoaderProvider)();
      final result = await ref.read(filmPreviewEngineProvider).render(
          source: source,
          recipe: catalog.recipe(widget.id),
          stage: PreviewStage.color,
          generation: 1);
      if (mounted) {
        setState(() {
          _source = source;
          _effect = result.image;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '参考预览暂不可用');
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: _effect != null
          ? ComparisonPreview(
              original: _source, effect: _effect, effectName: widget.name)
          : AspectRatio(
              aspectRatio: 3 / 2,
              child: ColoredBox(
                  color: GRemoteColors.raised,
                  child: Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : Text(_error!)))));
}
