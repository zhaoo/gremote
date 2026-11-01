import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../app/theme/app_colors.dart';
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
  bool _syncing = false, _importing = false;
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
    } catch (_) {
      if (mounted) setState(() => _error = '同步失败，已保留本地胶卷库');
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
    final local = catalog.valueOrNull;
    final films = cache?.films ??
        [
          for (final film in local?.entries ?? [])
            OfficialFilm(
                id: film.id,
                name: film.name,
                group: film.group,
                icon: film.icon)
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
    final groups = {
      '全部',
      ...films.map((f) => f.group),
      if (imported.isNotEmpty) '我的 LUT'
    };
    final visible = films
        .where((f) =>
            (_group == '全部' || f.group == _group) &&
            '${f.name} ${f.group}'.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(children: [
            Expanded(
                child: Text('${films.length} 款胶卷',
                    style: Theme.of(context).textTheme.bodyMedium)),
            IconButton(
                tooltip: '机内胶卷',
                onPressed: () => _openSlots(context),
                icon: const Icon(Icons.grid_view_outlined)),
            IconButton(
                tooltip: '导入 LUT',
                onPressed: _importing ? null : _import,
                icon: const Icon(Icons.add)),
            TextButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: _syncing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync, size: 18),
                label: const Text('同步')),
          ])),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(_error!,
                style: const TextStyle(color: GRemoteColors.danger))),
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                  hintText: '搜索胶卷',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: GRemoteColors.raised,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none)))),
      SizedBox(
          height: 48,
          child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final group in groups)
                  Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                          label: Text(group),
                          selected: _group == group,
                          onSelected: (_) => setState(() => _group = group)))
              ])),
      const Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 10),
          child: Row(children: [
            Expanded(flex: 3, child: Text('胶卷')),
            Expanded(flex: 2, child: Text('类型')),
            SizedBox(width: 24)
          ])),
      const Divider(height: 1),
      Expanded(
          child: catalog.isLoading && films.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : films.isEmpty
                  ? Center(child: Text(catalog.hasError ? '胶卷库读取失败' : '暂无胶卷'))
                  : visible.isEmpty && custom.isEmpty
                      ? const Center(child: Text('未找到胶卷'))
                      : ListView.separated(
                          itemCount: visible.length + custom.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, indent: 20, endIndent: 20),
                          itemBuilder: (context, index) {
                            if (index >= visible.length) {
                              final lut = custom[index - visible.length];
                              return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 8),
                                  leading: const Icon(Icons.tune_outlined),
                                  title: Text(lut.name),
                                  subtitle: const Text('我的 LUT · 照片编辑'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => showModalBottomSheet<void>(
                                      context: context,
                                      showDragHandle: true,
                                      builder: (sheet) => SafeArea(
                                          child: Padding(
                                              padding: const EdgeInsets.all(24),
                                              child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    Text(lut.name,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleLarge),
                                                    const SizedBox(height: 12),
                                                    const Text(
                                                        '手机编辑可用；当前机身不支持无线导入 LUT。'),
                                                    const SizedBox(height: 24),
                                                    FilledButton(
                                                        onPressed: () {
                                                          Navigator.pop(sheet);
                                                          context
                                                              .go('/library');
                                                        },
                                                        child:
                                                            const Text('选择照片')),
                                                    TextButton(
                                                        onPressed: () {
                                                          Navigator.pop(sheet);
                                                          context.push(
                                                              '/darkroom');
                                                        },
                                                        child: const Text(
                                                            '管理 LUT')),
                                                  ])))));
                            }
                            final film = visible[index];
                            final icon = local?.entries
                                    .where((f) => f.id == film.id)
                                    .firstOrNull
                                    ?.icon ??
                                film.icon;
                            return InkWell(
                                onTap: () => _details(film, local),
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 16),
                                    child: Row(children: [
                                      Expanded(
                                          flex: 3,
                                          child: Row(children: [
                                            SizedBox.square(
                                                dimension: 36,
                                                child: icon.startsWith('https:')
                                                    ? Image.network(icon,
                                                        errorBuilder: (_, __,
                                                                ___) =>
                                                            const Icon(Icons
                                                                .local_movies_outlined))
                                                    : Image.asset(icon,
                                                        errorBuilder: (_, __,
                                                                ___) =>
                                                            const Icon(Icons
                                                                .local_movies_outlined))),
                                            const SizedBox(width: 12),
                                            Expanded(
                                                child: Text(film.name,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600)))
                                          ])),
                                      Expanded(
                                          flex: 2,
                                          child: Text(film.group,
                                              style: const TextStyle(
                                                  color: GRemoteColors.muted))),
                                      const Icon(Icons.chevron_right,
                                          size: 20, color: GRemoteColors.muted),
                                    ])));
                          },
                        )),
    ]);
  }

  void _openSlots(BuildContext context, {int? filmId}) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('机内胶卷')),
            body: SafeArea(child: CameraFilmsPage(initialFilmId: filmId)))));
  }

  Future<void> _details(OfficialFilm film, CameraFilmCatalog? catalog) async {
    final supported = catalog?.entries.any((f) => f.id == film.id) ?? false;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: .86,
            minChildSize: .4,
            maxChildSize: .95,
            builder: (_, scroll) => ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                    children: [
                      Text(film.name,
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      Text(film.group,
                          style: const TextStyle(color: GRemoteColors.gold)),
                      if (film.description.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(film.description)),
                      const SizedBox(height: 24),
                      _FilmReference(id: film.id, name: film.name),
                      const SizedBox(height: 12),
                      const Text('参考预览 · AI 场景，本地调色；机内成片以实际拍摄为准',
                          style: TextStyle(
                              color: GRemoteColors.muted, fontSize: 12)),
                      const SizedBox(height: 24),
                      FilledButton(
                          onPressed: supported
                              ? () {
                                  Navigator.pop(sheet);
                                  _openSlots(context, filmId: film.id);
                                }
                              : null,
                          child: Text(supported ? '装入相机' : '需要更新机身胶卷目录')),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: () {
                            Navigator.pop(sheet);
                            context.push('/darkroom');
                          },
                          child: const Text('LUT 与出图方案')),
                    ])));
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
