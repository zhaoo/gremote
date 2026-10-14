import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../darkroom/export/export_service.dart';
import '../../../darkroom/model/export_recipe.dart';
import '../widgets/name_dialog.dart';
import 'editor_controller.dart';
import 'widgets/editor_panels.dart';
import 'widgets/frame_preview.dart';

/// Full-screen darkroom editor for one local photo.
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({required this.mediaId, super.key});

  final int mediaId;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  var _showOriginal = false;

  EditorController get _controller =>
      ref.read(editorProvider(widget.mediaId).notifier);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider(widget.mediaId));
    final layout = state.layout;
    return Scaffold(
      appBar: AppBar(
        title: Text(state.item?.displayName ?? '暗房'),
        actions: [
          TextButton(
            onPressed: state.doc == null ? null : _savePreset,
            child: const Text('存为方案'),
          ),
        ],
      ),
      body: layout == null
          ? Center(
              child: Text(state.error ?? '',
                  style: Theme.of(context).textTheme.bodyMedium))
          : DefaultTabController(
              length: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onLongPressStart: (_) =>
                          setState(() => _showOriginal = true),
                      onLongPressEnd: (_) =>
                          setState(() => _showOriginal = false),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: FramePreview(
                          key: const ValueKey('frame-preview'),
                          layout: layout,
                          image: _showOriginal ? state.base : state.graded,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    state.error ?? (_showOriginal ? '原图' : '长按预览查看原图'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: state.error == null
                            ? GRemoteColors.muted
                            : GRemoteColors.danger,
                        fontSize: 11),
                  ),
                  const TabBar(tabs: [
                    Tab(text: 'LUT'),
                    Tab(text: '边框'),
                    Tab(text: '画幅'),
                    Tab(text: '信息'),
                    Tab(text: '导出'),
                  ]),
                  SizedBox(
                    height: 220,
                    child: TabBarView(children: [
                      LutPanel(state: state, controller: _controller),
                      FrameStylePanel(state: state, controller: _controller),
                      ChoicePanel<FrameRatio>(
                        values: FrameRatio.values,
                        selected: state.recipe.ratio,
                        label: (v) => v.label,
                        onSelected: _controller.setRatio,
                        note: '固定画幅只增加留白，不裁切照片',
                      ),
                      InfoPanel(state: state, controller: _controller),
                      ExportPanel(state: state, controller: _controller),
                    ]),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: FilledButton(
                        onPressed: state.exporting ? null : _export,
                        child: Text(state.exporting ? '导出中…' : '导出'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final outcome = await _controller.export();
      messenger.showSnackBar(SnackBar(
        content: Text('已导出 ${outcome.displayName}'),
        action: SnackBarAction(
            label: '分享', onPressed: () => _controller.share(outcome.uri)),
      ));
    } on ExportCancelled {
      messenger.showSnackBar(const SnackBar(content: Text('导出已取消')));
    } on ExportFailure catch (failure) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导出失败'),
          content: Text('${failure.message}\n\n${failure.hint}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('知道了')),
          ],
        ),
      );
    }
  }

  Future<void> _savePreset() async {
    final saved =
        await showNameDialog(context, title: '存为方案', hint: '方案名称，如“夜街”');
    if (saved == null || !mounted) return;
    await _controller.savePreset(saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已保存方案「$saved」')));
  }
}
