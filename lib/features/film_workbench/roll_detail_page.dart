import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../darkroom/darkroom_providers.dart';
import '../../film/capture/active_roll_context.dart';
import '../../film/capture/local_roll_importer.dart';
import '../../film/model/film_roll.dart';
import '../../media/local/media_gateway.dart';
import 'roll_export_page.dart';
import 'workbench_providers.dart';
import 'widgets/workbench_style.dart';

final rollThumbnailProvider =
    FutureProvider.autoDispose.family<Uint8List?, RollItem>((ref, item) async {
  if (item.mediaId == null) return null;
  final gateway = ref.watch(mediaGatewayProvider);
  try {
    if (item.identity.instanceId == 'local-photo' &&
        await gateway.contentHash(item.mediaId!) != item.identity.contentHash) {
      return null;
    }
    return gateway.thumbnail(item.mediaId!, 384);
  } catch (_) {
    return null;
  }
});

class RollDetailPage extends ConsumerStatefulWidget {
  const RollDetailPage({super.key, required this.rollId});
  final String rollId;
  @override
  ConsumerState<RollDetailPage> createState() => _RollDetailPageState();
}

class _RollDetailPageState extends ConsumerState<RollDetailPage> {
  String? _error;
  bool _busy = false;
  Future<void> _import(FilmRoll roll) async {
    final entries = await showModalBottomSheet<List<LocalMediaEntry>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        sheetAnimationStyle: workbenchSheetAnimation(context),
        builder: (_) => const _ImportPhotosSheet());
    if (entries == null || entries.isEmpty || !mounted) return;
    setState(() => _busy = true);
    var done = 0;
    final failures = <String>[];
    try {
      final repository = ref.read(filmRepositoryProvider),
          gateway = ref.read(mediaGatewayProvider);
      final recipe = await repository.recipe(roll.recipeFingerprint);
      final importer =
          LocalRollImporter(repository: repository, gateway: gateway);
      for (final entry in entries) {
        if (!mounted) break;
        try {
          await importer.import(
              rollId: roll.id, mediaId: entry.id, recipe: recipe);
          done++;
        } catch (_) {
          failures.add(entry.displayName);
        }
      }
      ref.read(filmRollRevisionProvider.notifier).state++;
      if (mounted) {
        setState(() => _error = failures.isEmpty
            ? '已导入 $done 张 · 配方由你指定'
            : '已导入 $done 张，${failures.length} 张未能归档（原片不可用或已在其他胶卷中）');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close(FilmRoll roll) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('结束这一卷？'),
                content: const Text('照片和配方会完整保留，之后仍能导入照片或导出印样。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('继续拍摄')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('结束并出片'))
                ]));
    if (yes != true || !mounted) return;
    try {
      await ref.read(filmRepositoryProvider).closeRoll(roll.id);
      if (ref.read(activeRollCaptureContextProvider)?.rollId == roll.id) {
        ref.read(activeRollCaptureContextProvider.notifier).state = null;
      }
      ref.read(filmRollRevisionProvider.notifier).state++;
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _export(FilmRoll roll, List<RollItem> items) async {
    try {
      final recipe =
          await ref.read(filmRepositoryProvider).recipe(roll.recipeFingerprint);
      if (mounted) {
        await Navigator.push<void>(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    RollExportPage(roll: roll, items: items, recipe: recipe)));
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rolls = ref.watch(filmRollsProvider),
        items = ref.watch(rollItemsProvider(widget.rollId));
    return Scaffold(
        backgroundColor: context.palette.background,
        appBar: AppBar(
            title: const Text('数字胶卷'),
            backgroundColor: context.palette.background),
        body: rolls.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('$error')),
            data: (rolls) {
              final found = rolls.where((r) => r.id == widget.rollId);
              if (found.isEmpty) return const Center(child: Text('胶卷不存在'));
              final roll = found.single;
              return items.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text('照片读取失败：$error')),
                  data: (items) => CustomScrollView(slivers: [
                        SliverToBoxAdapter(
                            child: Padding(
                                padding: const EdgeInsets.all(22),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(roll.name,
                                          style: TextStyle(
                                              fontSize: 30,
                                              fontWeight: FontWeight.w700,
                                              color: context.palette.text)),
                                      const SizedBox(height: 12),
                                      Text(
                                          '${items.length} / ${roll.targetCount} 张 · ${roll.status == FilmRollStatus.open ? '拍摄中' : '已结束'}',
                                          style: TextStyle(
                                              color: context.palette.accent)),
                                      const SizedBox(height: 24),
                                      if (items.isEmpty)
                                        Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 32),
                                            child: Text(
                                                '这一卷还没有照片。\n导入真实照片，开始整理今天的片段。',
                                                style: TextStyle(
                                                    color:
                                                        context.palette.muted,
                                                    height: 1.8))),
                                      Wrap(
                                          spacing: 10,
                                          runSpacing: 8,
                                          children: [
                                            OutlinedButton.icon(
                                                onPressed: _busy
                                                    ? null
                                                    : () => _import(roll),
                                                icon: const Icon(Icons
                                                    .add_photo_alternate_outlined),
                                                label: Text(
                                                    _busy ? '正在归档…' : '导入照片')),
                                            FilledButton.icon(
                                                onPressed: () =>
                                                    _export(roll, items),
                                                icon: const Icon(
                                                    Icons.grid_on_outlined),
                                                label: const Text('联系印样 / 配方卡'))
                                          ]),
                                      if (roll.status == FilmRollStatus.open)
                                        TextButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _close(roll),
                                            child: const Text('结束这一卷，去冲洗 ↗')),
                                      if (_error != null)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 12),
                                            child: Text(_error!,
                                                style: TextStyle(
                                                    color: context
                                                        .palette.accent))),
                                      const SizedBox(height: 8),
                                      Text('点按星标加入精选 · 导入不改变原片色彩',
                                          style: TextStyle(
                                              color: context.palette.muted,
                                              fontSize: 11)),
                                    ]))),
                        SliverPadding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                            sliver: SliverGrid(
                                delegate:
                                    SliverChildBuilderDelegate((context, i) {
                                  final item = items[i],
                                      thumb = ref
                                          .watch(rollThumbnailProvider(item));
                                  return Container(
                                      color: context.palette.raised,
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                                child: SizedBox(
                                                    width: double.infinity,
                                                    child: thumb.when(
                                                        loading: () => Center(
                                                            child: Icon(Icons.photo_outlined,
                                                                color: context
                                                                    .palette
                                                                    .muted)),
                                                        error: (_, __) =>
                                                            const Center(
                                                                child: Icon(Icons
                                                                    .broken_image_outlined)),
                                                        data: (bytes) => bytes == null
                                                            ? Center(child: Icon(Icons.hide_image_outlined, color: context.palette.muted))
                                                            : Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 384)))),
                                            Row(children: [
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          left: 8),
                                                  child: Text(
                                                      '${i + 1}'
                                                          .padLeft(2, '0'),
                                                      style: TextStyle(
                                                          color: context
                                                              .palette.accent,
                                                          fontSize: 11))),
                                              const Spacer(),
                                              IconButton(
                                                  tooltip: item.selected
                                                      ? '取消精选'
                                                      : '加入精选',
                                                  onPressed: () async {
                                                    await ref
                                                        .read(
                                                            filmRepositoryProvider)
                                                        .setSelected(item.id,
                                                            !item.selected);
                                                    ref
                                                        .read(
                                                            filmRollRevisionProvider
                                                                .notifier)
                                                        .state++;
                                                  },
                                                  icon: Icon(
                                                      item.selected
                                                          ? Icons.star_rounded
                                                          : Icons
                                                              .star_border_rounded,
                                                      color: context
                                                          .palette.accent,
                                                      size: 20))
                                            ]),
                                            Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                        8, 0, 8, 8),
                                                child: Text(
                                                    switch (item.confidence) {
                                                      RecipeConfidence
                                                            .cameraConfirmed =>
                                                        '相机已确认',
                                                      RecipeConfidence
                                                            .userAssigned =>
                                                        '用户指定配方',
                                                      RecipeConfidence
                                                            .unverified =>
                                                        '配方未验证'
                                                    },
                                                    maxLines: 1,
                                                    style: TextStyle(
                                                        color: context
                                                            .palette.muted,
                                                        fontSize: 9))),
                                          ]));
                                }, childCount: items.length),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 180,
                                        childAspectRatio: .85,
                                        crossAxisSpacing: 8,
                                        mainAxisSpacing: 8))),
                      ]));
            }));
  }
}

class _ImportPhotosSheet extends ConsumerStatefulWidget {
  const _ImportPhotosSheet();
  @override
  ConsumerState<_ImportPhotosSheet> createState() => _ImportPhotosSheetState();
}

class _ImportPhotosSheetState extends ConsumerState<_ImportPhotosSheet> {
  final _selected = <int>{};
  late final Future<List<LocalMediaEntry>> _entries = _load();
  Future<List<LocalMediaEntry>> _load() async {
    final gateway = ref.read(mediaGatewayProvider);
    if (await gateway.requestAccess() == MediaAccess.denied) {
      throw const MediaException('permissionDenied', '请允许访问照片');
    }
    return gateway.queryImages();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: FutureBuilder<List<LocalMediaEntry>>(
              future: _entries,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('相册不可用：${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = snapshot.data!;
                return Column(children: [
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(children: [
                        const Expanded(
                            child:
                                Text('导入照片', style: TextStyle(fontSize: 22))),
                        TextButton(
                            onPressed: _selected.isEmpty
                                ? null
                                : () => Navigator.pop(
                                    context,
                                    entries
                                        .where((e) => _selected.contains(e.id))
                                        .toList()),
                            child: Text('归档 ${_selected.length} 张'))
                      ])),
                  const Padding(
                      padding: EdgeInsets.fromLTRB(22, 8, 22, 16),
                      child: Text('使用本卷配方标记所选照片，不重新套色。请确认配方与原片相符。',
                          style: TextStyle(fontSize: 12))),
                  if (entries.isEmpty)
                    const Expanded(
                        child: Center(child: Text('授权范围内还没有 JPEG 照片'))),
                  if (entries.isNotEmpty)
                    Expanded(
                        child: ListView.builder(
                            itemCount: entries.length,
                            itemBuilder: (context, i) => CheckboxListTile(
                                value: _selected.contains(entries[i].id),
                                title: Text(entries[i].displayName),
                                subtitle: Text(
                                    '${entries[i].width} × ${entries[i].height}'),
                                onChanged: (selected) => setState(() {
                                      if (selected == true) {
                                        _selected.add(entries[i].id);
                                      } else {
                                        _selected.remove(entries[i].id);
                                      }
                                    })))),
                ]);
              })));
}
