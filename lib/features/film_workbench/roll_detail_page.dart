import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../library/album_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../darkroom/darkroom_providers.dart';
import '../../film/capture/active_roll_context.dart';
import '../../film/capture/local_roll_importer.dart';
import '../../film/model/film_roll.dart';
import '../../media/local/media_gateway.dart';
import 'roll_export_page.dart';
import 'workbench_providers.dart';
import 'widgets/workbench_style.dart';
import '../library/live_gallery_page.dart';
import 'roll_archive_actions.dart';
import 'roll_photo_page.dart';

final rollThumbnailProvider =
    FutureProvider.autoDispose.family<Uint8List?, RollItem>((ref, item) async {
  if (item.mediaId == null) return null;
  final gateway = ref.watch(mediaGatewayProvider);
  try {
    final hash = item.originalPreviewHash;
    if (hash != null && await gateway.contentHash(item.mediaId!) != hash) {
      return null;
    }
    return await gateway.thumbnail(item.mediaId!, 384);
  } catch (_) {
    return null;
  }
});

class RollDetailPage extends ConsumerStatefulWidget {
  const RollDetailPage(
      {super.key, required this.rollId, this.openExport = false});
  final String rollId;
  final bool openExport;
  @override
  ConsumerState<RollDetailPage> createState() => _RollDetailPageState();
}

class _RollDetailPageState extends ConsumerState<RollDetailPage> {
  String? _error;
  bool _busy = false;
  bool _openedExport = false;
  Future<void> _import(FilmRoll roll) async {
    final fingerprint = roll.recipeFingerprint;
    if (fingerprint == null) return;
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
      final recipe = await repository.recipe(fingerprint);
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
      final fingerprint = roll.recipeFingerprint;
      final recipe = fingerprint == null
          ? null
          : await ref.read(filmRepositoryProvider).recipe(fingerprint);
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
        entries = ref.watch(rollItemsProvider(widget.rollId));
    return Theme(
        data: albumTheme(context),
        child: Builder(
            builder: (context) => rolls.when(
                  loading: () => const Scaffold(
                      body: Center(child: CircularProgressIndicator())),
                  error: (error, _) => Scaffold(
                      appBar: AppBar(title: const Text('胶卷')),
                      body: Center(child: Text('胶卷读取失败：$error'))),
                  data: (rolls) {
                    final roll =
                        rolls.where((r) => r.id == widget.rollId).firstOrNull;
                    if (roll == null) {
                      return Scaffold(
                          appBar: AppBar(title: const Text('胶卷')),
                          body: const Center(child: Text('胶卷记录已删除')));
                    }
                    return entries.when(
                        loading: () => const Scaffold(
                            body: Center(child: CircularProgressIndicator())),
                        error: (error, _) => Scaffold(
                            appBar: AppBar(title: const Text('胶卷')),
                            body: Center(child: Text('照片读取失败：$error'))),
                        data: (items) {
                          if (widget.openExport &&
                              !_openedExport &&
                              items.isNotEmpty) {
                            _openedExport = true;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _export(roll, items);
                            });
                          }
                          return Scaffold(
                              appBar: AppBar(
                                  title: const Text('胶卷',
                                      style: TextStyle(fontSize: 18)),
                                  centerTitle: true,
                                  actions: [
                                    PopupMenuButton<String>(
                                        tooltip: '胶卷更多',
                                        icon: const Icon(Icons.more_horiz),
                                        onSelected: (value) async {
                                          if (value == 'import') {
                                            await _import(roll);
                                          } else if (value == 'export') {
                                            await _export(roll, items);
                                          } else if (value == 'close') {
                                            await _close(roll);
                                          } else if (value == 'delete') {
                                            try {
                                              final deleted =
                                                  await deleteLocalRollArchive(
                                                      context, ref, roll.id);
                                              if (deleted && context.mounted) {
                                                Navigator.of(context)
                                                    .maybePop();
                                              }
                                            } catch (_) {
                                              if (mounted) {
                                                setState(
                                                    () => _error = '删除失败，请重试');
                                              }
                                            }
                                          }
                                        },
                                        itemBuilder: (_) => [
                                              if (roll.recipeFingerprint !=
                                                  null)
                                                PopupMenuItem(
                                                    value: 'import',
                                                    enabled: !_busy,
                                                    child: const Text('添加照片')),
                                              PopupMenuItem(
                                                  value: 'export',
                                                  enabled: !_busy &&
                                                      items.isNotEmpty,
                                                  child: const Text('导出印样')),
                                              if (roll.status ==
                                                  FilmRollStatus.open)
                                                PopupMenuItem(
                                                    value: 'close',
                                                    enabled: !_busy,
                                                    child: const Text('结束这一卷')),
                                              const PopupMenuDivider(),
                                              PopupMenuItem(
                                                  value: 'delete',
                                                  enabled: !_busy,
                                                  child: const Text('删除胶卷')),
                                            ])
                                  ]),
                              body: CustomScrollView(slivers: [
                                SliverToBoxAdapter(
                                    child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            22, 20, 22, 26),
                                        child: Row(children: [
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(roll.name,
                                                    style: const TextStyle(
                                                        fontSize: 25,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                const SizedBox(height: 8),
                                                Text(
                                                    '${items.length} / ${roll.targetCount} 张 · ${roll.statusLabel}',
                                                    style: TextStyle(
                                                        color: context
                                                            .palette.muted,
                                                        fontSize: 12))
                                              ])),
                                          const AlbumTag('手机'),
                                        ]))),
                                if (_busy)
                                  const SliverToBoxAdapter(
                                      child: LinearProgressIndicator(
                                          minHeight: 2)),
                                if (_error != null)
                                  SliverToBoxAdapter(
                                      child: AlbumNotice(_error!)),
                                if (items.isEmpty)
                                  SliverToBoxAdapter(
                                      child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 58, horizontal: 24),
                                          child: Column(children: [
                                            Text('还没有照片',
                                                style: TextStyle(
                                                    fontSize: 14,
                                                    color:
                                                        context.palette.muted)),
                                            const SizedBox(height: 12),
                                            if (roll.recipeFingerprint != null)
                                              OutlinedButton.icon(
                                                  onPressed: _busy
                                                      ? null
                                                      : () => _import(roll),
                                                  icon: const Icon(
                                                      Icons
                                                          .add_photo_alternate_outlined,
                                                      size: 18),
                                                  label: const Text('添加照片'))
                                          ]))),
                                SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 0, 20, 24),
                                    sliver: SliverGrid(
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: 3,
                                                childAspectRatio: .72,
                                                mainAxisSpacing: 6,
                                                crossAxisSpacing: 6),
                                        delegate: SliverChildBuilderDelegate(
                                            (context, i) {
                                          final item = items[i],
                                              thumb = ref.watch(
                                                  rollThumbnailProvider(
                                                      items[i]));
                                          final rawOnly = item
                                                  .files.isNotEmpty &&
                                              item.files.every((file) => file
                                                  .toUpperCase()
                                                  .endsWith('.DNG'));
                                          return ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                              child: Container(
                                                  color: context.palette.raised,
                                                  child: Column(children: [
                                                    Expanded(
                                                        child: InkWell(
                                                            key: ValueKey(
                                                                'roll-photo-${item.id}'),
                                                            onTap: item.mediaId ==
                                                                    null
                                                                ? null
                                                                : () => Navigator.of(
                                                                        context)
                                                                    .push(MaterialPageRoute<
                                                                            void>(
                                                                        builder: (_) =>
                                                                            RollPhotoPage(
                                                                                item))),
                                                            child: Stack(
                                                                fit: StackFit
                                                                    .expand,
                                                                children: [
                                                                  thumb.when(
                                                                      loading: () => const Center(
                                                                          child: Icon(Icons
                                                                              .photo_outlined)),
                                                                      error: (_, __) => Center(
                                                                          child: Icon(rawOnly
                                                                              ? Icons
                                                                                  .raw_on_outlined
                                                                              : Icons
                                                                                  .broken_image_outlined)),
                                                                      data: (data) => data ==
                                                                              null
                                                                          ? Center(
                                                                              child: Icon(rawOnly ? Icons.raw_on_outlined : Icons.hide_image_outlined))
                                                                          : Image.memory(data, fit: BoxFit.cover, cacheWidth: 384, errorBuilder: (_, __, ___) => Center(child: Icon(rawOnly ? Icons.raw_on_outlined : Icons.broken_image_outlined)))),
                                                                  if (rawOnly)
                                                                    const Positioned(
                                                                        top: 5,
                                                                        right:
                                                                            5,
                                                                        child: AlbumTag(
                                                                            'RAW')),
                                                                ]))),
                                                    Row(children: [
                                                      Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  left: 7),
                                                          child: Text(
                                                              '${item.frameNumber ?? i + 1}'
                                                                  .padLeft(
                                                                      2, '0'),
                                                              style: TextStyle(
                                                                  fontSize: 10,
                                                                  color: context
                                                                      .palette
                                                                      .muted))),
                                                      const Spacer(),
                                                      SizedBox(
                                                          width: 34,
                                                          height: 34,
                                                          child: IconButton(
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              tooltip:
                                                                  item.selected
                                                                      ? '取消精选'
                                                                      : '加入精选',
                                                              onPressed:
                                                                  () async {
                                                                await ref
                                                                    .read(
                                                                        filmRepositoryProvider)
                                                                    .setSelected(
                                                                        item.id,
                                                                        !item
                                                                            .selected);
                                                                ref
                                                                    .read(filmRollRevisionProvider
                                                                        .notifier)
                                                                    .state++;
                                                              },
                                                              icon: Icon(
                                                                  item.selected
                                                                      ? Icons
                                                                          .star
                                                                      : Icons
                                                                          .star_border,
                                                                  size: 18,
                                                                  color: context
                                                                      .palette
                                                                      .accent)))
                                                    ])
                                                  ])));
                                        }, childCount: items.length))),
                              ]));
                        });
                  },
                )));
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
