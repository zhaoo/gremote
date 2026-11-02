import 'dart:async';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/widgets/workspace_motion.dart';
import '../../../darkroom/darkroom_providers.dart';
import '../../../darkroom/export/export_service.dart';
import '../../../darkroom/frame/frame_layout.dart';
import '../../../darkroom/model/export_recipe.dart';
import '../../../darkroom/model/photo_edits.dart';
import '../widgets/name_dialog.dart';
import 'editor_controller.dart';
import 'widgets/adjustment_panel.dart';
import 'widgets/crop_panel.dart';
import 'widgets/curve_panel.dart';
import 'widgets/editor_panels.dart';
import 'widgets/editor_tools.dart';
import 'widgets/frame_preview.dart';
import 'widgets/lut_picker.dart';

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({required this.mediaId, super.key});
  final int mediaId;
  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  var _showOriginal = false;
  var _allowPop = false;
  var _leaving = false;
  EditorTool? _tool;
  PhotoAdjustment? _activeAdjustment;
  double _photoDrag = 0;
  double _dragValue = 0;
  final _zoom = TransformationController();
  EditorController get _controller =>
      ref.read(editorProvider(widget.mediaId).notifier);

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _open(EditorTool tool) {
    if (tool == EditorTool.presets) {
      _presets();
      return;
    }
    if (tool == EditorTool.history) {
      _history();
      return;
    }
    _controller.beginTool(crop: tool == EditorTool.crop);
    setState(() {
      _tool = tool;
      _activeAdjustment = tool.adjustments.firstOrNull;
      _showOriginal = false;
      _zoom.value = Matrix4.identity();
    });
  }

  void _finish({bool cancel = false}) {
    if (cancel) {
      _controller.cancelTool();
    } else {
      _controller.commitTool();
    }
    setState(() {
      _tool = null;
      _showOriginal = false;
      _zoom.value = Matrix4.identity();
    });
  }

  Future<void> _leave() async {
    if (_leaving || ref.read(editorProvider(widget.mediaId)).exporting) return;
    if (_tool != null) {
      _finish();
      return;
    }
    _leaving = true;
    _controller.commitTool();
    await _controller.flushEdits();
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
      _leaving = false;
    });
  }

  bool _changed(EditorTool t, EditorState s) {
    if (t == EditorTool.crop) return s.recipe.edits.crop != const CropEdit();
    if (t == EditorTool.lut) return s.recipe.lutId != null;
    if (t == EditorTool.frame) return s.recipe.frame != FrameStyle.none;
    if (t == EditorTool.curves) {
      return s.recipe.edits.curves.any((c) => c != const ToneCurve());
    }
    if (t == EditorTool.stamp) return s.recipe.dateStamp;
    return t.adjustments.any((a) => s.recipe.edits.value(a) != a.initial);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(editorProvider(widget.mediaId));
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final media = MediaQuery.sizeOf(context);
    final height = (_tool == null ? media.height * .41 : media.height * .32)
        .clamp(190.0, _tool == null ? 374.0 : 318.0);
    return PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leave();
        },
        child: Scaffold(
            backgroundColor: GRemoteColors.night,
            appBar: AppBar(
                automaticallyImplyLeading: false,
                leading: IconButton(
                    tooltip: '返回相册',
                    onPressed: s.exporting ? null : _leave,
                    icon: const Icon(Icons.chevron_left, size: 24)),
                titleSpacing: 0,
                title: Text(s.item?.displayName ?? '照片编辑',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14)),
                actions: [
                  Tooltip(
                      message: '按住对比',
                      child: Semantics(
                          button: true,
                          label: '对比原图',
                          value: _showOriginal ? '原图' : '编辑后',
                          onTap: () =>
                              setState(() => _showOriginal = !_showOriginal),
                          child: Listener(
                              onPointerDown: (_) =>
                                  setState(() => _showOriginal = true),
                              onPointerUp: (_) =>
                                  setState(() => _showOriginal = false),
                              onPointerCancel: (_) =>
                                  setState(() => _showOriginal = false),
                              child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Icon(Icons.compare_outlined,
                                      size: 21,
                                      color: _showOriginal
                                          ? GRemoteColors.text
                                          : GRemoteColors.muted))))),
                  PopupMenuButton<String>(
                      tooltip: '更多',
                      enabled: !s.exporting,
                      icon: const Icon(Icons.more_horiz, size: 22),
                      onSelected: _more,
                      itemBuilder: (_) => [
                            for (final label in [
                              '存为方案',
                              '信息',
                              '画幅',
                              '导出',
                              '还原全部'
                            ])
                              PopupMenuItem(value: label, child: Text(label))
                          ]),
                  Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: FilledButton(
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(50, 36),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10)),
                          onPressed:
                              s.doc == null || s.base == null || s.exporting
                                  ? null
                                  : _export,
                          child: Text(s.exporting ? '导出中…' : '导出',
                              style: const TextStyle(fontSize: 12))))
                ]),
            body: s.layout == null
                ? Center(child: Text(s.error ?? '读取照片…'))
                : SafeArea(
                    top: false,
                    child: AbsorbPointer(
                        absorbing: s.exporting,
                        child: landscape
                            ? Row(children: [
                                Expanded(child: _photo(s)),
                                SizedBox(
                                    width: math.min(360, media.width * .47),
                                    child: _workspace(s))
                              ])
                            : Column(children: [
                                Expanded(child: _photo(s)),
                                _status(s),
                                AnimatedContainer(
                                    duration:
                                        WorkspaceMotion.duration(context, 180),
                                    curve: Curves.easeOutCubic,
                                    height: height,
                                    child: _workspace(s))
                              ])))));
  }

  Widget _photo(EditorState s) {
    final original = _showOriginal;
    final meta = s.meta!;
    final layout = original
        ? computeFrameLayout(
            photoWidth: meta.orientedWidth,
            photoHeight: meta.orientedHeight,
            style: FrameStyle.none,
            ratio: FrameRatio.original,
            content: const FrameContent())
        : s.layout!;
    Widget photo = FramePreview(
        key: const ValueKey('frame-preview'),
        layout: layout,
        image: original ? s.base : s.graded);
    if (s.cropEditing && !original) {
      photo = Center(
          child: AspectRatio(
              aspectRatio: layout.canvasWidth / layout.canvasHeight,
              child: CropSelection(
                  crop: s.recipe.edits.crop,
                  onStart: _controller.beginGesture,
                  onEnd: _controller.endGesture,
                  onChanged: (c) =>
                      _controller.setEdits(s.recipe.edits.copyWith(crop: c)),
                  child: photo)));
    } else {
      photo = InteractiveViewer(
          transformationController: _zoom,
          minScale: 1,
          maxScale: 5,
          panEnabled: _tool == null,
          scaleEnabled: _tool == null,
          child: photo);
    }
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (_) => setState(() => _showOriginal = true),
            onLongPressEnd: (_) => setState(() => _showOriginal = false),
            onLongPressCancel: () => setState(() => _showOriginal = false),
            onDoubleTap: () => _zoom.value = Matrix4.identity(),
            onHorizontalDragStart: _tool?.adjustments.isNotEmpty == true
                ? (d) {
                    _controller.beginGesture();
                    _photoDrag = 0;
                    _dragValue = s.recipe.edits
                        .value((_activeAdjustment ?? _tool!.adjustments.first));
                  }
                : null,
            onHorizontalDragUpdate: _tool?.adjustments.isNotEmpty == true
                ? (d) {
                    _photoDrag += d.delta.dx;
                    final a = (_activeAdjustment ?? _tool!.adjustments.first);
                    _controller.setEdits(ref
                        .read(editorProvider(widget.mediaId))
                        .recipe
                        .edits
                        .withValue(
                            a,
                            (_dragValue + _photoDrag / 250 * (a.max - a.min))
                                .clamp(a.min, a.max)));
                  }
                : null,
            onHorizontalDragEnd: _tool?.adjustments.isNotEmpty == true
                ? (_) => _controller.endGesture()
                : null,
            onHorizontalDragCancel: _tool?.adjustments.isNotEmpty == true
                ? _controller.endGesture
                : null,
            child: Stack(fit: StackFit.expand, children: [
              photo,
              if (original)
                Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: GRemoteColors.raised,
                            borderRadius: BorderRadius.circular(5)),
                        child:
                            const Text('原图', style: TextStyle(fontSize: 12))))
            ])));
  }

  Widget _status(EditorState s) => SizedBox(
      height: 40,
      child: Row(children: [
        const SizedBox(width: 12),
        IconButton(
            tooltip: '撤销',
            icon: const Icon(Icons.undo, size: 18),
            onPressed: s.canUndo && !s.exporting ? _controller.undo : null),
        IconButton(
            tooltip: '重做',
            icon: const Icon(Icons.redo, size: 18),
            onPressed: s.canRedo && !s.exporting ? _controller.redo : null),
        Expanded(
            child: GestureDetector(
                onTap: s.error == null && s.saveError == null
                    ? null
                    : () {
                        _controller.retrySave();
                        _controller.regrade();
                      },
                child: Text(
                    s.saveError ??
                        s.error ??
                        (s.rendering
                            ? '预览中…'
                            : s.saving
                                ? '保存中…'
                                : _tool == null
                                    ? '已保存'
                                    : '调整中'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        color: s.error == null && s.saveError == null
                            ? GRemoteColors.muted
                            : GRemoteColors.danger)))),
        IconButton(
            tooltip: '重置当前工具',
            icon: const Icon(Icons.restart_alt, size: 19),
            onPressed: _tool == null || s.exporting ? null : _resetTool),
        const SizedBox(width: 12)
      ]));

  Widget _workspace(EditorState s) {
    final tool = _tool;
    return ColoredBox(
        color: GRemoteColors.raised,
        child: Column(children: [
          if (MediaQuery.sizeOf(context).width >
              MediaQuery.sizeOf(context).height)
            _status(s),
          Expanded(
              child: SingleChildScrollView(
                  key: ValueKey(tool),
                  child: AnimatedSwitcher(
                      duration: WorkspaceMotion.duration(context, 140),
                      child: tool == null
                          ? EditorTools(
                              key: const ValueKey('editor-tools'),
                              onSelected: _open,
                              changed: (t) => _changed(t, s))
                          : _panel(tool, s)))),
          SizedBox(
              height: 53,
              child: tool == null
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                          TextButton(
                              onPressed: _presets, child: const Text('预设')),
                          const Text('工具', style: TextStyle(fontSize: 13)),
                          TextButton(
                              onPressed: _export, child: const Text('导出'))
                        ])
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                          IconButton(
                              tooltip: '取消调整',
                              onPressed: () => _finish(cancel: true),
                              icon: const Icon(Icons.close, size: 21)),
                          Text(tool.label,
                              style: const TextStyle(
                                  fontSize: 13, color: GRemoteColors.muted)),
                          IconButton(
                              tooltip: '完成调整',
                              onPressed: () => _finish(),
                              icon: const Icon(Icons.check, size: 21))
                        ]))
        ]));
  }

  Widget _panel(EditorTool tool, EditorState s) {
    if (tool.adjustments.isNotEmpty) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (tool == EditorTool.grain)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(spacing: 8, children: [
                for (final p in [('细腻', .18), ('35mm', .32), ('粗颗粒', .6)])
                  TextButton(
                      onPressed: () => _controller.setEdits(s.recipe.edits
                          .withValue(PhotoAdjustment.grain, p.$2)),
                      child: Text(p.$1, style: const TextStyle(fontSize: 12)))
              ])),
        if (tool == EditorTool.leak)
          Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: () => _controller.setEdits(s.recipe.edits.copyWith(
                      seed: (s.recipe.edits.seed * 1664525 + 1013904223) %
                              16777215 +
                          1)),
                  child: const Text('换一个'))),
        AdjustmentPanel(
            key: ValueKey(tool),
            edits: s.recipe.edits,
            adjustments: tool.adjustments,
            onChanged: _controller.setEdits,
            onActiveChanged: (a) => _activeAdjustment = a,
            onStart: _controller.beginGesture,
            onEnd: _controller.endGesture)
      ]);
    }
    switch (tool) {
      case EditorTool.curves:
        return CurvePanel(
            edits: s.recipe.edits,
            histogramSource: s.graded,
            onChanged: _controller.setEdits,
            onStart: _controller.beginGesture,
            onEnd: _controller.endGesture);
      case EditorTool.crop:
        return CropPanel(
            crop: s.recipe.edits.crop,
            sourceWidth: s.meta!.orientedWidth,
            sourceHeight: s.meta!.orientedHeight,
            onChanged: (c) => _controller.setEdits(ref
                .read(editorProvider(widget.mediaId))
                .recipe
                .edits
                .copyWith(crop: c)),
            onStart: _controller.beginGesture,
            onEnd: _controller.endGesture);
      case EditorTool.lut:
        return LutPicker(
            source: s.base,
            edits: s.recipe.edits,
            entries: s.luts,
            selected: s.recipe.lutId,
            strength: s.recipe.strength,
            onSelected: _controller.setLut,
            onStrength: _controller.setStrength,
            onStart: _controller.beginGesture,
            onEnd: _controller.endGesture,
            onImport: _importLut);
      case EditorTool.frame:
        return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final style in [
                      FrameStyle.none,
                      FrameStyle.white,
                      FrameStyle.black,
                      FrameStyle.classic,
                      FrameStyle.polaroid,
                      FrameStyle.contact,
                      FrameStyle.street
                    ])
                      ChoiceChip(
                          label: Text(style.label,
                              style: const TextStyle(fontSize: 12)),
                          selected: s.recipe.frame == style,
                          showCheckmark: false,
                          onSelected: (_) => _controller.setFrame(style))
                  ]),
              if (s.recipe.frame != FrameStyle.none) ...[
                const SizedBox(height: 16),
                Text('宽度 ${(s.recipe.frameWidth * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 13)),
                Slider(
                    value: s.recipe.frameWidth,
                    min: 0,
                    max: .2,
                    onChangeStart: (_) => _controller.beginGesture(),
                    onChanged: _controller.setFrameWidth,
                    onChangeEnd: (_) => _controller.endGesture())
              ]
            ]));
      case EditorTool.stamp:
        return Padding(
            padding: const EdgeInsets.all(16),
            child: SwitchListTile(
                title: const Text('日期印记'),
                subtitle: Text(s.meta?.dateLabel ?? '照片没有拍摄日期'),
                value: s.recipe.dateStamp,
                onChanged: s.meta?.dateLabel == null
                    ? null
                    : _controller.setDateStamp));
      default:
        return const SizedBox.shrink();
    }
  }

  void _resetTool() {
    final tool = _tool;
    if (tool == null) return;
    final s = ref.read(editorProvider(widget.mediaId));
    var e = s.recipe.edits;
    for (final a in tool.adjustments) {
      e = e.withValue(a, a.initial);
    }
    if (tool == EditorTool.crop) e = e.copyWith(crop: const CropEdit());
    if (tool == EditorTool.curves) {
      e = e.copyWith(
          curves: const [ToneCurve(), ToneCurve(), ToneCurve(), ToneCurve()]);
    }
    _controller.beginGesture();
    _controller.setEdits(e);
    if (tool == EditorTool.lut) _controller.setLut(null);
    if (tool == EditorTool.frame) {
      _controller.setFrame(FrameStyle.none);
      _controller.setFrameWidth(.035);
    }
    if (tool == EditorTool.stamp) _controller.setDateStamp(false);
    _controller.endGesture();
  }

  Future<void> _importLut() async {
    try {
      final file = await openFile(acceptedTypeGroups: [
        const XTypeGroup(label: 'LUT', extensions: ['cube'])
      ]);
      if (file == null || !mounted) return;
      if (await file.length() > 16 * 1024 * 1024) {
        _notice('LUT 文件不能超过 16 MiB');
        return;
      }
      await _controller.importLut(file.name, await file.readAsBytes());
    } on Object catch (e) {
      if (mounted) _notice('导入失败：$e');
    }
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _more(String action) async {
    if (action == '存为方案') {
      await _savePreset();
      return;
    }
    if (action == '还原全部') {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(title: const Text('还原全部调整？'), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('还原'))
              ]));
      if (confirmed == true && mounted) _controller.resetAll();
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .6,
                child: Consumer(builder: (context, ref, _) {
                  final s = ref.watch(editorProvider(widget.mediaId));
                  return Column(children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
                        child: Row(children: [
                          Text(action),
                          const Spacer(),
                          IconButton(
                              tooltip: '关闭',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close, size: 20))
                        ])),
                    Expanded(
                        child: action == '信息'
                            ? InfoPanel(state: s, controller: _controller)
                            : action == '画幅'
                                ? ChoicePanel<FrameRatio>(
                                    values: FrameRatio.values,
                                    selected: s.recipe.ratio,
                                    label: (v) => v.label,
                                    onSelected: _controller.setRatio,
                                    note: '增加留白，保留完整照片')
                                : ExportPanel(
                                    state: s, controller: _controller))
                  ]);
                }))));
  }

  Future<void> _presets() async {
    final presets = await ref.read(darkroomStoreProvider).presets();
    if (!mounted) return;
    await showModalBottomSheet<void>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    children: [
                  Row(children: [
                    const Text('预设'),
                    const Spacer(),
                    TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _savePreset();
                        },
                        child: const Text('保存当前'))
                  ]),
                  if (presets.isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('还没有保存的预设',
                            style: TextStyle(color: GRemoteColors.muted))),
                  for (final preset in presets)
                    ListTile(
                        title: Text(preset.name),
                        onTap: () {
                          _controller.applyPreset(preset.recipe);
                          Navigator.pop(context);
                        })
                ])));
  }

  Future<void> _history() async {
    final s = ref.read(editorProvider(widget.mediaId));
    await showModalBottomSheet<void>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    children: [
                  const ListTile(title: Text('当前调整')),
                  for (final tool
                      in EditorTool.values.where((t) => _changed(t, s)))
                    ListTile(
                        leading: Icon(tool.icon, size: 20),
                        title: Text(tool.label),
                        onTap: () {
                          Navigator.pop(context);
                          _open(tool);
                        }),
                  if (!EditorTool.values.any((t) => _changed(t, s)))
                    const ListTile(title: Text('尚未调整'))
                ])));
  }

  Future<void> _export() async {
    if (_tool != null) _finish();
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
