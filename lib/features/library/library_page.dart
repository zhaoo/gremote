import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../darkroom/export/export_queue.dart';
import '../../darkroom/model/export_recipe.dart';
import '../../media/local/local_media_repository.dart';
import '../../media/local/media_gateway.dart';
import 'library_controller.dart';
import 'camera_gallery.dart';
import 'widgets/media_grid.dart';
import 'widgets/recipe_sheet.dart';

enum _Source { local, camera }

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  var _source = _Source.local;
  late final AppLifecycleListener _lifecycle;

  LibraryController get _controller =>
      ref.read(libraryControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Permission may change in system settings while we are away.
    _lifecycle = AppLifecycleListener(onResume: () => _controller.refresh());
    Future.microtask(_controller.refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(children: [
                Text('图库', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                SegmentedButton<_Source>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _Source.local, label: Text('本机')),
                    ButtonSegment(value: _Source.camera, label: Text('相机')),
                  ],
                  selected: {_source},
                  onSelectionChanged: (value) {
                    final next = value.single;
                    if (_source != _Source.local && next == _Source.local) {
                      unawaited(_controller.refresh());
                    }
                    setState(() => _source = next);
                  },
                ),
              ]),
            ),
            Expanded(
              child: _source == _Source.camera
                  ? const CameraGallery()
                  : _LocalLibrary(state: state, controller: _controller),
            ),
          ],
        ),
      ),
      bottomNavigationBar: state.selecting && _source == _Source.local
          ? _SelectionBar(
              count: state.selected.length,
              showConfirm: state.selectedHasUnconfirmedWeak,
              onCancel: _controller.clearSelection,
              onExport: _startBatch,
              onRecipeExport: _startRecipeBatch,
              onConfirm: _controller.confirmSelectedTags,
            )
          : null,
    );
  }

  Future<void> _startRecipeBatch() async {
    final result = await _controller.recipeJobs();
    if (!mounted) return;
    if (result.jobs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选照片没有可用的组合配方出图方案')),
      );
      return;
    }
    if (result.skipped > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('部分照片将跳过'),
          content: Text('${result.skipped} 张没有已确认的配方或出图方案。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    final queue = ref.read(exportQueueProvider.notifier);
    if (ref.read(exportQueueProvider).running) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已有导出任务在进行')));
      return;
    }
    unawaited(queue.startEach(result.jobs));
    _controller.clearSelection();
    unawaited(context.push('/export-queue'));
  }

  Future<void> _startBatch() async {
    final items = _controller.selectedItems;
    final recipe = await showModalBottomSheet<ExportRecipe>(
      context: context,
      backgroundColor: GRemoteColors.navy,
      builder: (_) => RecipeSheet(count: items.length),
    );
    if (recipe == null || !mounted) return;
    final queue = ref.read(exportQueueProvider.notifier);
    if (ref.read(exportQueueProvider).running) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已有导出任务在进行')));
    } else {
      unawaited(queue.start(items, recipe));
      _controller.clearSelection();
    }
    unawaited(context.push('/export-queue'));
  }
}

class _LocalLibrary extends StatelessWidget {
  const _LocalLibrary({required this.state, required this.controller});

  final LibraryState state;
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final access = state.access;
    if (access == null) return const SizedBox.shrink();
    if (access == MediaAccess.denied) {
      return _AccessCard(onRequest: controller.requestAccess);
    }
    final scan = state.scan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (access == MediaAccess.partial)
          InkWell(
            onTap: controller.requestAccess,
            child: Container(
              color: GRemoteColors.raised,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: const Text('仅显示你允许的照片 · 继续添加',
                  style:
                      TextStyle(color: GRemoteColors.goldSoft, fontSize: 13)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 20, 8),
          child: Row(children: [
            ChoiceChip(
              label: const Text('GR III'),
              selected: state.grOnly,
              onSelected: (_) => controller.setGrOnly(true),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('全部'),
              selected: !state.grOnly,
              onSelected: (_) => controller.setGrOnly(false),
            ),
            const SizedBox(width: 8),
            const Spacer(),
            Text('${state.items.length} 张',
                style:
                    const TextStyle(color: GRemoteColors.muted, fontSize: 12)),
          ]),
        ),
        if (scan != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('正在读取 EXIF ${scan.done}/${scan.total}',
                    style: const TextStyle(
                        color: GRemoteColors.muted, fontSize: 12)),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: scan.total == 0 ? 0 : scan.done / scan.total,
                  color: GRemoteColors.gold,
                  backgroundColor: GRemoteColors.divider,
                ),
              ],
            ),
          ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(state.error!,
                style:
                    const TextStyle(color: GRemoteColors.danger, fontSize: 12)),
          ),
        Expanded(
          child: state.items.isEmpty
              ? Center(
                  child: Text(
                    scan != null
                        ? '正在整理相册…'
                        : state.grOnly
                            ? '没有找到 GR III 拍摄的 JPEG'
                            : '相册里没有 JPEG',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : MediaGrid(
                  items: state.items,
                  selected: state.selected,
                  tags: state.tags,
                  onTap: (item) => state.selecting
                      ? controller.toggle(item.id)
                      : context.push('/edit/${item.id}'),
                  onLongPress: (LocalMediaItem item) =>
                      controller.toggle(item.id),
                ),
        ),
      ],
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.onRequest});

  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.photo_library_outlined,
                size: 40, color: GRemoteColors.goldSoft),
            const SizedBox(height: 18),
            Text('访问本机照片', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('用于调色、加边框并导出副本；原图永远不会被修改。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 22),
            FilledButton(onPressed: onRequest, child: const Text('允许访问照片')),
          ]),
        ),
      );
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.showConfirm,
    required this.onCancel,
    required this.onExport,
    required this.onRecipeExport,
    required this.onConfirm,
  });

  final int count;
  final bool showConfirm;
  final VoidCallback onCancel;
  final VoidCallback onExport;
  final VoidCallback onRecipeExport;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: const BoxDecoration(
            color: GRemoteColors.navy,
            border: Border(top: BorderSide(color: GRemoteColors.divider)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              TextButton(onPressed: onCancel, child: const Text('取消')),
              Text('已选 $count',
                  style: const TextStyle(color: GRemoteColors.muted)),
              const Spacer(),
              if (showConfirm)
                TextButton(
                  onPressed: () => unawaited(onConfirm()),
                  child: const Text('确认配方'),
                ),
            ]),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onRecipeExport,
                  child: const Text('按配方导出'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onExport,
                  child: Text('批量出图 ($count)'),
                ),
              ),
            ]),
          ]),
        ),
      );
}
