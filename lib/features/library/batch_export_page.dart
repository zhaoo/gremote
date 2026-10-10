import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../darkroom/export/export_queue.dart';

/// Progress and results of the current batch export.
class BatchExportPage extends ConsumerWidget {
  const BatchExportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exportQueueProvider);
    final queue = ref.read(exportQueueProvider.notifier);
    final done = state.count(ExportItemStatus.done);
    final failed = state.count(ExportItemStatus.failed);
    return Scaffold(
      appBar: AppBar(title: const Text('批量出图')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text('完成 $done · 失败 $failed · 共 ${state.items.length}',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          if (state.running)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('导出期间请保持 GRemote 在前台，切到后台可能被系统暂停',
                  style: TextStyle(color: GRemoteColors.muted, fontSize: 12)),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: state.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = state.items[index];
                final failure = entry.failure;
                return ListTile(
                  title: Text(entry.item.displayName),
                  subtitle: failure == null
                      ? (entry.outcome == null
                          ? null
                          : Text(entry.outcome!.displayName,
                              style: const TextStyle(
                                  color: GRemoteColors.muted, fontSize: 12)))
                      : Text('${failure.message}\n${failure.hint}',
                          style: const TextStyle(
                              color: GRemoteColors.danger, fontSize: 12)),
                  isThreeLine: failure != null,
                  trailing: Text(entry.status.label,
                      style: TextStyle(
                          color: switch (entry.status) {
                        ExportItemStatus.done => GRemoteColors.gold,
                        ExportItemStatus.failed => GRemoteColors.danger,
                        _ => GRemoteColors.muted,
                      })),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: state.running
                  ? OutlinedButton(
                      onPressed: queue.cancel, child: const Text('取消导出'))
                  : Row(children: [
                      if (failed > 0)
                        Expanded(
                          child: FilledButton(
                              onPressed: queue.retryFailed,
                              child: Text('重试失败项 ($failed)')),
                        ),
                      if (failed > 0) const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            queue.clear();
                            Navigator.of(context).pop();
                          },
                          child: const Text('完成'),
                        ),
                      ),
                    ]),
            ),
          ),
        ],
      ),
    );
  }
}
