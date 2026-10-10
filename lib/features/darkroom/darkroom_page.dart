import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../darkroom/lut/lut_library.dart';
import '../../darkroom/store/darkroom_store.dart';
import '../library/widgets/recipe_sheet.dart';
import 'darkroom_controller.dart';
import 'widgets/name_dialog.dart';

class DarkroomPage extends ConsumerWidget {
  const DarkroomPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(darkroomOverviewProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: overview.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
              child: Text('暗房数据读取失败：$error',
                  style: const TextStyle(color: GRemoteColors.danger))),
          data: (data) => _Overview(data: data),
        ),
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({required this.data});

  final DarkroomOverview data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(darkroomActionsProvider);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              Text('暗房', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              const Text('DEVELOP YOUR LOOK',
                  style: TextStyle(
                      color: GRemoteColors.gold, fontSize: 9, letterSpacing: 1.6)),
            ]),
          ),
        ),
        _header(context, '最近编辑', 'RECENT EDITS'),
        if (data.edits.isEmpty)
          _empty('还没有编辑记录；从图库打开一张照片开始。')
        else
          SliverList.builder(
            itemCount: data.edits.length,
            itemBuilder: (context, index) {
              final edit = data.edits[index];
              return ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: Text(
                    edit.title.isEmpty ? '照片 #${edit.mediaId}' : edit.title),
                subtitle: Text(
                    '${edit.recipe.frame.label} · ${edit.recipe.ratio.label} · ${edit.recipe.size.label}',
                    style:
                        const TextStyle(color: GRemoteColors.muted, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/edit/${edit.mediaId}'),
              );
            },
          ),
        _header(context, 'LUT 库', 'COLOR LIBRARY',
            action: TextButton.icon(
              onPressed: () => _import(context, actions),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('导入 LUT'),
            )),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: data.luts.length,
            itemBuilder: (context, index) {
              final lut = data.luts[index];
              return _LutCard(
                key: lut.imported ? null : const ValueKey('builtin-lut'),
                lut: lut,
                onDelete: lut.imported
                    ? () => _delete(context, '删除 LUT「${lut.name}」？',
                        () => actions.deleteLut(lut.id))
                    : null,
              );
            },
          ),
        ),
        _header(context, '出图方案', 'EXPORT PRESETS'),
        if (data.presets.isEmpty)
          _empty('在编辑页点“存为方案”，即可批量复用。')
        else
          SliverList.builder(
            itemCount: data.presets.length,
            itemBuilder: (context, index) => _PresetTile(
              preset: data.presets[index],
              onRename: () => _rename(context, actions, data.presets[index]),
              onDelete: () => _delete(
                  context,
                  '删除方案「${data.presets[index].name}」？',
                  () => actions.deletePreset(data.presets[index].id)),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }

  SliverPadding _header(BuildContext context, String title, String kicker,
          {Widget? action}) =>
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 24, 12, 8),
        sliver: SliverToBoxAdapter(
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(kicker,
                  style: const TextStyle(
                      color: GRemoteColors.gold, fontSize: 8, letterSpacing: 1.5)),
            ]),
            const Spacer(),
            if (action != null) action,
          ]),
        ),
      );

  SliverPadding _empty(String text) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        sliver: SliverToBoxAdapter(
            child: Text(text,
                style: const TextStyle(color: GRemoteColors.muted, fontSize: 13))),
      );

  Future<void> _import(BuildContext context, DarkroomActions actions) async {
    try {
      await actions.importLut();
    } on LutImportException catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('LUT 导入失败'),
          content: Text(e.reason),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了')),
          ],
        ),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法读取 LUT 文件：$e')));
    }
  }

  Future<void> _rename(BuildContext context, DarkroomActions actions,
      ExportPreset preset) async {
    final name = await showNameDialog(context,
        title: '重命名方案', initial: preset.name, hint: '方案名称');
    if (name != null) await actions.renamePreset(preset.id, name);
  }

  Future<void> _delete(BuildContext context, String message,
      Future<void> Function() action) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (yes == true) await action();
  }
}

class _LutCard extends StatelessWidget {
  const _LutCard({required this.lut, this.onDelete, super.key});

  final LutEntry lut;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: GRemoteColors.navy,
          border: Border.all(color: GRemoteColors.divider),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
          child: Row(children: [
            Container(
              width: 5,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [
                  GRemoteColors.gold,
                  Color(0xFF516D65),
                  Color(0xFFCB7D5D),
                ], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(lut.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${lut.size} 点${lut.imported ? ' · 导入' : ''}',
                      style: const TextStyle(
                          color: GRemoteColors.muted, fontSize: 10)),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                key: const ValueKey('delete-lut'),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
          ]),
        ),
      );
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.onRename,
    required this.onDelete,
  });

  final ExportPreset preset;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(preset.name),
        subtitle: Text(describeRecipe(preset.recipe),
            style: const TextStyle(color: GRemoteColors.muted, fontSize: 12)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            key: ValueKey('rename-${preset.id}'),
            onPressed: onRename,
            icon: const Icon(Icons.edit_outlined, size: 19),
          ),
          IconButton(
            key: ValueKey('delete-${preset.id}'),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 19),
          ),
        ]),
      );
}
