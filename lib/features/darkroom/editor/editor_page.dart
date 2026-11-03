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

class _EditorPageState extends ConsumerState<EditorPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final session = ref.read(editorProvider(widget.mediaId)).gpuSession;
      if (session?.closed == true) {
        unawaited(_controller.recoverPreview());
      } else if (session != null) {
        unawaited(_controller.regrade());
      }
    }
  }

  void _compare(bool value) {
    setState(() => _showOriginal = value);
    _controller.compareOriginal(value);
  }

  var _showOriginal = false;
  var _allowPop = false;
  var _leaving = false;
  EditorTool? _tool;
  int _tab = 1, _presetRevision = 0;
  bool _presetDraft = false, _presetStrength = false;
  PhotoAdjustment? _activeAdjustment;
  double _photoDrag = 0;
  double _dragValue = 0;
  final _zoom = TransformationController();
  final _zoomKey = GlobalKey();
  Timer? _detailTimer;
  EditorController get _controller =>
      ref.read(editorProvider(widget.mediaId).notifier);

  @override
  void dispose() {
    _detailTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
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
    _controller.compareOriginal(false);
    _controller.beginTool(crop: tool == EditorTool.crop);
    setState(() {
      _tool = tool;
      _activeAdjustment = tool.adjustments.firstOrNull;
      _showOriginal = false;
      _zoom.value = Matrix4.identity();
    });
  }

  void _finish({bool cancel = false}) {
    _controller.compareOriginal(false);
    if (cancel) {
      _controller.cancelTool();
    } else {
      _controller.commitTool();
    }
    setState(() {
      _tool = null;
      _presetDraft = false;
      _presetStrength = false;
      _presetRevision++;
      _showOriginal = false;
      _zoom.value = Matrix4.identity();
    });
  }

  void _selectPreset(String? id) {
    _compare(false);
    final selected = ref.read(editorProvider(widget.mediaId)).recipe.lutId;
    if (_presetDraft && selected == id && id != null) {
      setState(() => _presetStrength = true);
      return;
    }
    if (!_presetDraft) _controller.beginTool();
    setState(() {
      _presetDraft = true;
      _presetStrength = false;
    });
    unawaited(_controller.setLut(id));
  }

  Widget _studioPresets(EditorState s) => LutPicker(
      key: ValueKey(('studio-presets', _presetRevision)),
      source: s.base,
      gpuSession: s.gpuSession,
      edits: s.recipe.edits,
      entries: s.luts,
      selected: s.recipe.lutId,
      strength: s.recipe.strength,
      grid: true,
      showStrength: _presetStrength,
      onSelected: _selectPreset,
      onStrength: _controller.setStrength,
      onStart: _controller.beginGesture,
      onEnd: _controller.endGesture,
      onImport: _importLut,
      onSchemes: _presets,
      onStrengthTap: () {
        if (s.recipe.lutId == null) return;
        if (!_presetDraft) {
          _controller.beginTool();
        }
        setState(() {
          _presetDraft = true;
          _presetStrength = !_presetStrength;
        });
      });
  Widget _records(EditorState s) {
    final history = _controller.history;
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
          child: Row(children: [
            Text('编辑记录',
                style: TextStyle(fontSize: 12, color: context.palette.muted)),
            const Spacer(),
            TextButton(
                onPressed: _savePreset,
                child: const Text('存为预设', style: TextStyle(fontSize: 12)))
          ])),
      for (var i = history.length - 1; i >= 0; i--)
        ListTile(
            dense: true,
            leading: Icon(
                i == history.length - 1
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16),
            title: Text(
                i == 0
                    ? '打开时'
                    : _recordLabel(history[i - 1].recipe, history[i].recipe),
                style: const TextStyle(fontSize: 12)),
            trailing: i == history.length - 1
                ? Text('当前',
                    style:
                        TextStyle(fontSize: 11, color: context.palette.muted))
                : null,
            onTap: i == history.length - 1
                ? null
                : () => _controller.restoreHistory(i)),
    ]);
  }

  String _recordLabel(ExportRecipe before, ExportRecipe after) {
    if (before.lutId != after.lutId) {
      return after.lutId == null
          ? '移除 LUT'
          : ref
                  .read(editorProvider(widget.mediaId))
                  .luts
                  .where((e) => e.id == after.lutId)
                  .firstOrNull
                  ?.name ??
              'LUT';
    }
    if (before.strength != after.strength) {
      return 'LUT · ${(after.strength * 100).round()}%';
    }
    if (before.edits.crop != after.edits.crop) return '裁切';
    if (before.edits.curves != after.edits.curves &&
        List.generate(4, (i) => i)
            .any((i) => before.edits.curves[i] != after.edits.curves[i])) {
      return '曲线';
    }
    final changed = PhotoAdjustment.values
        .where((a) => before.edits.value(a) != after.edits.value(a))
        .toList();
    if (changed.isNotEmpty) {
      return changed
          .take(2)
          .map((a) => '${a.label} ${a.display(after.edits.value(a))}')
          .join(' · ');
    }
    if (before.frame != after.frame || before.frameWidth != after.frameWidth) {
      return '边框';
    }
    if (before.dateStamp != after.dateStamp) return '日期印记';
    if (before.ratio != after.ratio) return '画幅';
    return '设置';
  }

  Widget _mainNavigation() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        for (var i = 0; i < 3; i++)
          Expanded(
              child: Semantics(
                  selected: _tab == i,
                  button: true,
                  child: InkWell(
                      key: ValueKey('studio-tab-$i'),
                      onTap: () => setState(() => _tab = i),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                                [
                                  Icons.auto_awesome_mosaic_outlined,
                                  Icons.tune,
                                  Icons.history
                                ][i],
                                size: 18,
                                color: _tab == i
                                    ? context.palette.text
                                    : context.palette.muted),
                            const SizedBox(height: 5),
                            Text(['预设', '调整', '记录'][i],
                                style: TextStyle(
                                    fontSize: 11,
                                    color: _tab == i
                                        ? context.palette.text
                                        : context.palette.muted,
                                    fontWeight: _tab == i
                                        ? FontWeight.w500
                                        : FontWeight.w400))
                          ])))),
      ]);

  Future<void> _leave() async {
    if (_leaving || ref.read(editorProvider(widget.mediaId)).exporting) return;
    if (_presetDraft) {
      _finish(cancel: true);
      return;
    }
    if (_tool != null) {
      _finish();
      return;
    }
    setState(() => _leaving = true);
    _controller.commitTool();
    await _controller.flushEdits();
    if (!mounted) return;
    if (ref.read(editorProvider(widget.mediaId)).saveError != null) {
      setState(() => _leaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('调整尚未保存，请重试后退出'),
          action: SnackBarAction(
              label: '重试',
              onPressed: () async {
                await _controller.retrySave();
                if (mounted) _leave();
              })));
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await Navigator.of(context).maybePop();
      if (mounted) setState(() => _leaving = false);
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
    final height = (_tool == EditorTool.curves
            ? media.height * .44
            : _tool == null
                ? media.height * .41
                : media.height * .32)
        .clamp(
            _tool == EditorTool.curves ? 290.0 : 190.0,
            _tool == EditorTool.curves
                ? 400.0
                : _tool == null
                    ? 374.0
                    : 318.0);
    return PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leave();
        },
        child: Scaffold(
            backgroundColor: context.palette.background,
            appBar: AppBar(
                automaticallyImplyLeading: false,
                leading: IconButton(
                    tooltip: '返回相册',
                    onPressed: s.exporting || _leaving ? null : _leave,
                    icon: const Icon(Icons.chevron_left, size: 24)),
                titleSpacing: 0,
                title: Text(s.item?.displayName ?? '照片编辑',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, letterSpacing: .7)),
                actions: [
                  Tooltip(
                      message: '按住对比',
                      child: Semantics(
                          button: true,
                          label: '对比原图',
                          value: _showOriginal ? '原图' : '编辑后',
                          onTap: () => _compare(!_showOriginal),
                          child: Listener(
                              onPointerDown: (_) => _compare(true),
                              onPointerUp: (_) => _compare(false),
                              onPointerCancel: (_) => _compare(false),
                              child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Icon(Icons.compare_outlined,
                                      size: 21,
                                      color: _showOriginal
                                          ? context.palette.text
                                          : context.palette.muted))))),
                  PopupMenuButton<String>(
                      tooltip: '更多',
                      enabled: !s.exporting && !_leaving,
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
                          onPressed: s.doc == null ||
                                  s.base == null ||
                                  s.exporting ||
                                  _leaving
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
                        absorbing: s.exporting || _leaving,
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

  void _requestDetail(EditorState s) {
    if (!mounted ||
        _tool != null ||
        _showOriginal ||
        _zoom.value.getMaxScaleOnAxis() < 1.35) return;
    final box = _zoomKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || s.layout == null) return;
    final size = box.size,
        layout = s.layout!,
        ratio = layout.canvasWidth / layout.canvasHeight;
    final frameWidth = math.min(size.width, size.height * ratio),
        frameHeight = frameWidth / ratio;
    final scale = frameWidth / layout.canvasWidth, p = layout.photo;
    final photo = Rect.fromLTWH(
        (size.width - frameWidth) / 2 + p.x * scale,
        (size.height - frameHeight) / 2 + p.y * scale,
        p.width * scale,
        p.height * scale);
    final visible = Rect.fromPoints(_zoom.toScene(Offset.zero),
            _zoom.toScene(Offset(size.width, size.height)))
        .intersect(photo);
    if (visible.isEmpty) return;
    unawaited(_controller.detailAt(Rect.fromLTWH(
        (visible.left - photo.left) / photo.width,
        (visible.top - photo.top) / photo.height,
        visible.width / photo.width,
        visible.height / photo.height)));
  }

  Widget _photo(EditorState s) {
    final original =
        s.gpuSession == null ? _showOriginal : (s.gpuFrame?.original ?? false);
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
        image: original ? s.base : s.graded,
        detail: original ? null : s.detail,
        textureId: s.gpuSession?.closed == true ? null : s.gpuFrame?.textureId);
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
          key: _zoomKey,
          onInteractionStart: (_) => _detailTimer?.cancel(),
          onInteractionEnd: (_) {
            _detailTimer?.cancel();
            _detailTimer = Timer(
                const Duration(milliseconds: 200), () => _requestDetail(s));
          },
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
            onLongPressStart: (_) => _compare(true),
            onLongPressEnd: (_) => _compare(false),
            onLongPressCancel: () => _compare(false),
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
                            color: context.palette.raised,
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
                        if (s.saveError != null) _controller.retrySave();
                        if (s.error != null) {
                          if (s.gpuSession != null ||
                              ref.read(gpuEditorProvider) != null) {
                            _controller.recoverPreview();
                          } else {
                            _controller.regrade();
                          }
                        }
                      },
                child: Text(s.saveError ?? s.error ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        color: s.error == null && s.saveError == null
                            ? context.palette.muted
                            : context.palette.danger)))),
        IconButton(
            tooltip: '重置当前工具',
            icon: const Icon(Icons.restart_alt, size: 19),
            onPressed: _tool == null || s.exporting ? null : _resetTool),
        const SizedBox(width: 12)
      ]));

  Widget _workspace(EditorState s) {
    final tool = _tool;
    return ColoredBox(
        color: context.palette.raised,
        child: Column(children: [
          if (MediaQuery.sizeOf(context).width >
              MediaQuery.sizeOf(context).height)
            _status(s),
          Expanded(
              child: SingleChildScrollView(
                  key: ValueKey(tool),
                  child: AnimatedSwitcher(
                      duration: WorkspaceMotion.duration(context, 160),
                      child: tool == null
                          ? _tab == 0
                              ? _studioPresets(s)
                              : _tab == 2
                                  ? _records(s)
                                  : EditorTools(
                                      key: const ValueKey('editor-tools'),
                                      onSelected: _open,
                                      changed: (t) => _changed(t, s))
                          : _panel(tool, s)))),
          SizedBox(
              height: 53,
              child: tool == null && !_presetDraft
                  ? _mainNavigation()
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                          IconButton(
                              tooltip: '取消调整',
                              onPressed: () => _finish(cancel: true),
                              icon: const Icon(Icons.close, size: 21)),
                          Text(_presetDraft ? "预设" : tool!.label,
                              style: TextStyle(
                                  fontSize: 13, color: context.palette.muted)),
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
            histogramBins: s.histogram,
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
            gpuSession: s.gpuSession,
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
      if (_tab == 0 && _tool == null && !_presetDraft) {
        _controller.beginTool();
        setState(() => _presetDraft = true);
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
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text('还没有保存的预设',
                            style: TextStyle(color: context.palette.muted))),
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
    if (_tool != null || _presetDraft) _finish();
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
