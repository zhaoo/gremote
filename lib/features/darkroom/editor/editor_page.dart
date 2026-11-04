import 'dart:async';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/widgets/workspace_motion.dart';
import '../../../darkroom/darkroom_providers.dart';
import '../../../film/catalog/official_lut_selection.dart';
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
import 'widgets/editor_ruler.dart';
import 'widgets/frame_preview.dart';
import 'widgets/lut_picker.dart';

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({required this.mediaId, this.initialLut, super.key});
  final int mediaId;
  final String? initialLut;
  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (officialLutSelection(widget.initialLut) != null) {
      ref.listenManual(editorProvider(widget.mediaId), (_, next) {
        _queueInitialLut(next);
      }, fireImmediately: true);
    }
  }

  bool _initialLutHandled = false, _initialLutScheduled = false;
  void _queueInitialLut(EditorState state) {
    if (_initialLutHandled ||
        _initialLutScheduled ||
        state.doc == null ||
        state.luts.isEmpty) return;
    _initialLutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialLutScheduled = false;
      if (!mounted || _initialLutHandled) return;
      final current = ref.read(editorProvider(widget.mediaId));
      if (current.doc == null || current.luts.isEmpty) return;
      _initialLutHandled = true;
      final id = officialLutSelection(widget.initialLut);
      if (id != null &&
          current.luts.any((entry) => entry.id == id && entry.official)) {
        unawaited(_controller.setLut(id));
      }
    });
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
    if (_showOriginal == value) return;
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
  double _photoDrag = 0, _parameterDrag = 0;
  int _parameterStart = 0;
  bool _parametersOpen = false;
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
    if (tool == EditorTool.processVersion) {
      _controller.beginProcessUpgrade();
    } else {
      _controller.beginTool(crop: tool == EditorTool.crop);
    }
    setState(() {
      _tool = tool;
      _parametersOpen = false;
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
      _parametersOpen = false;
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
        strip: true,
        showStrength: _presetStrength,
        onSelected: _selectPreset,
        onStrength: _controller.setStrength,
        onStart: _controller.beginGesture,
        onEnd: _controller.endGesture,
        onImport: _importLut,
      );
  Widget _records(BuildContext sheetContext) {
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
                : () {
                    _controller.restoreHistory(i);
                    Navigator.of(sheetContext).pop();
                  }),
    ]);
  }

  String _recordLabel(ExportRecipe before, ExportRecipe after) {
    if (before.edits.processVersion != after.edits.processVersion) {
      return after.edits.processVersion == 2 ? '新版调色' : '原有调色';
    }
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

  bool _canExport(EditorState s) =>
      s.doc != null &&
      (s.base != null ||
          (s.gpuFrame != null && s.gpuSession?.closed == false)) &&
      !s.exporting &&
      !_leaving;

  Widget _mainNavigation(EditorState s) => SizedBox(
      height: 56,
      child: Row(children: [
        for (var i = 0; i < 2; i++)
          Expanded(
              child: Semantics(
            selected: _tab == i,
            button: true,
            child: InkWell(
              key: ValueKey('studio-tab-$i'),
              onTap: s.layout == null ? null : () => setState(() => _tab = i),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_tab == i)
                      const SizedBox(
                          height: 15,
                          child: Center(child: EditorChevron(up: true)))
                    else
                      const SizedBox(height: 15),
                    Text(i == 0 ? '样式' : '工具',
                        style: TextStyle(
                            color: context.palette.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ]),
            ),
          )),
        Expanded(
            child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: context.palette.text,
            disabledForegroundColor: context.palette.muted,
            elevation: 0,
            shape: const RoundedRectangleBorder(),
            padding: const EdgeInsets.only(top: 12),
          ),
          onPressed: _canExport(s) ? _export : null,
          child: Text(s.exporting ? '导出中…' : '导出',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        )),
      ]));

  Future<void> _leave() async {
    if (_leaving || ref.read(editorProvider(widget.mediaId)).exporting) return;
    if (_parametersOpen) {
      setState(() => _parametersOpen = false);
      return;
    }
    if (_presetDraft) {
      _finish(cancel: true);
      return;
    }
    if (_tool != null) {
      _finish(cancel: true);
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

  Widget _headerButton(String label, IconData icon, VoidCallback? pressed) =>
      IconButton(
        tooltip: label,
        onPressed: pressed,
        icon: Icon(icon, size: 21),
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        padding: EdgeInsets.zero,
      );

  PreferredSizeWidget _header(EditorState s, Color background) {
    final tool = _tool;
    final enabled = !s.exporting && !_leaving;
    final compare = s.base != null || s.gpuFrame != null;
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Row(children: [
          if (tool == null)
            _headerButton('返回相册', Icons.arrow_back, enabled ? _leave : null)
          else
            Expanded(
                child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox.square(
                    dimension: 5,
                    child: ColoredBox(
                      color: tool == EditorTool.crop
                          ? const Color(0xffd976d8)
                          : const Color(0xff368ac8),
                    )),
                const SizedBox(width: 5),
                Flexible(
                    child: Text(tool.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13))),
              ]),
            )),
          if (tool == null) const Spacer(),
          _headerButton(
              '撤销', Icons.undo, enabled && s.canUndo ? _controller.undo : null),
          if (tool == null && !_presetDraft)
            _headerButton('编辑记录', Icons.layers_outlined,
                enabled && s.doc != null ? _showRecords : null),
          _headerButton(
              '重做', Icons.redo, enabled && s.canRedo ? _controller.redo : null),
          if (tool == null) const Spacer(),
          Tooltip(
            message: '按住对比',
            child: Semantics(
              button: true,
              enabled: enabled && compare,
              label: '对比原图',
              value: _showOriginal ? '原图' : '编辑后',
              onTap: enabled && compare ? () => _compare(!_showOriginal) : null,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown:
                    enabled && compare ? (_) => _compare(true) : null,
                onPointerUp: enabled && compare ? (_) => _compare(false) : null,
                onPointerCancel:
                    enabled && compare ? (_) => _compare(false) : null,
                child: SizedBox.square(
                    dimension: 44,
                    child: Icon(
                      Icons.compare_outlined,
                      size: 21,
                      color: compare
                          ? context.palette.text
                          : context.palette.muted,
                    )),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            enabled: enabled && s.doc != null,
            icon: const Icon(Icons.more_vert, size: 21),
            onSelected: _more,
            itemBuilder: (_) => [
              for (final label in [
                if (tool == null && _tab == 0) '全部样式',
                if (tool == null && !_presetDraft && _tab == 0) ...[
                  '导入 LUT',
                  '我的预设',
                  if (s.recipe.lutId != null) '样式强度',
                ],
                if (tool == null &&
                    !_presetDraft &&
                    s.recipe.edits.processVersion == 1)
                  '新版调色',
                '存为方案',
                '信息',
                '画幅',
                '导出',
                '还原全部',
              ])
                PopupMenuItem(value: label, child: Text(label))
            ],
          ),
        ]),
      ),
    );
  }

  Future<void> _showRecords() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
              child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .7),
            child: SingleChildScrollView(child: _records(context)),
          )));

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(editorProvider(widget.mediaId));
    final media = MediaQuery.sizeOf(context);
    final landscape = media.width > media.height;
    final background = Theme.of(context).brightness == Brightness.light
        ? const Color(0xfff1f0ea)
        : context.palette.background;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: background,
        appBar: _header(s, background),
        body: SafeArea(
          top: false,
          child: AbsorbPointer(
            absorbing: s.exporting || _leaving,
            child: landscape
                ? Row(children: [
                    Expanded(child: _stage(s, overlayCurve: false)),
                    SizedBox(
                        width: math.min(370, media.width * .49),
                        child: _workspace(s, overlayCurve: false)),
                  ])
                : Column(children: [
                    Expanded(child: _stage(s, overlayCurve: true)),
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxHeight: media.height * .42),
                      child: _workspace(s, overlayCurve: true),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }

  Widget _stage(EditorState s, {required bool overlayCurve}) {
    final curve =
        overlayCurve && _tool == EditorTool.curves && s.layout != null;
    return Stack(fit: StackFit.expand, children: [
      Padding(
        padding: EdgeInsets.only(bottom: curve ? 60 : 0),
        child: s.layout == null ? _loadingPhoto(s.error) : _photo(s),
      ),
      if (curve) _curve(s, overlay: true),
      if (_parametersOpen && _tool?.adjustments.isNotEmpty == true)
        _parameterOverlay(s),
    ]);
  }

  Widget _parameterOverlay(EditorState s) {
    final adjustments = _tool!.adjustments;
    final active = _activeAdjustment;
    return Stack(fit: StackFit.expand, children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _parametersOpen = false),
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(
              begin: Colors.transparent, end: const Color(0x99111111)),
          duration: WorkspaceMotion.duration(context, 100),
          builder: (_, color, __) =>
              ColoredBox(color: color ?? Colors.transparent),
        ),
      ),
      Center(
        child: SingleChildScrollView(
          child: Material(
            color: const Color(0xba171914),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final a in adjustments)
                Semantics(
                  selected: a == active,
                  child: InkWell(
                    key: ValueKey(('editor-parameter', a)),
                    onTap: () => setState(() {
                      _activeAdjustment = a;
                      _parametersOpen = false;
                    }),
                    child: Ink(
                      color: a == active ? editorMarker : Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: SizedBox(
                            height: 41,
                            child: Row(children: [
                              Expanded(
                                  child: Text(a.label,
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: a == active
                                              ? const Color(0xff181a15)
                                              : Colors.white))),
                              Text(a.display(s.recipe.edits.value(a)),
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                      color: a == active
                                          ? const Color(0xff181a15)
                                          : Colors.white)),
                            ])),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }

  void _startParameterDrag(List<PhotoAdjustment> adjustments) {
    _parameterDrag = 0;
    _parameterStart = math.max(0, adjustments.indexOf(_activeAdjustment!));
    setState(() => _parametersOpen = true);
  }

  void _updateParameterDrag(double delta, List<PhotoAdjustment> adjustments) {
    _parameterDrag += delta;
    final index = (_parameterStart + (_parameterDrag / 35).round())
        .clamp(0, adjustments.length - 1);
    if (_activeAdjustment != adjustments[index]) {
      setState(() => _activeAdjustment = adjustments[index]);
    }
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

  Widget _loadingPhoto(String? error) {
    // Reuse the album's bounded, oriented source thumbnail. It is only a
    // loading aid; it never becomes the edited frame or an export source.
    final bytes = ref.watch(thumbnailProvider(widget.mediaId)).valueOrNull;
    return Stack(fit: StackFit.expand, children: [
      if (bytes != null)
        Padding(
            padding: const EdgeInsets.all(16),
            child: Image.memory(bytes,
                key: const ValueKey('editor-loading-thumbnail'),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink())),
      Align(
          alignment: bytes == null ? Alignment.center : Alignment.bottomCenter,
          child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: context.palette.raised,
                  borderRadius: BorderRadius.circular(5)),
              child: Text(error ?? '正在载入编辑…',
                  style: const TextStyle(fontSize: 12)))),
    ]);
  }

  Widget _photo(EditorState s) {
    if (s.base == null && s.gpuFrame == null) return _loadingPhoto(s.error);
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
    } else if (_tool == null) {
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
          child: photo);
    }
    final adjustments = _tool?.adjustments ?? const <PhotoAdjustment>[];
    final canSwitch = adjustments.length > 1;
    return Padding(
        padding: EdgeInsets.symmetric(horizontal: s.cropEditing ? 16 : 0),
        child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (_) => _compare(true),
            onLongPressEnd: (_) => _compare(false),
            onLongPressCancel: () => _compare(false),
            onDoubleTap:
                _tool == null ? () => _zoom.value = Matrix4.identity() : null,
            onVerticalDragStart:
                canSwitch ? (_) => _startParameterDrag(adjustments) : null,
            onVerticalDragUpdate: canSwitch
                ? (d) => _updateParameterDrag(d.delta.dy, adjustments)
                : null,
            onVerticalDragEnd: canSwitch
                ? (_) => setState(() => _parametersOpen = false)
                : null,
            onVerticalDragCancel: canSwitch
                ? () {
                    if (_parametersOpen) {
                      setState(() => _parametersOpen = false);
                    }
                  }
                : null,
            onHorizontalDragStart: _tool?.adjustments.isNotEmpty == true
                ? (d) {
                    _controller.beginGesture();
                    _photoDrag = 0;
                    _dragValue = ref
                        .read(editorProvider(widget.mediaId))
                        .recipe
                        .edits
                        .value(_activeAdjustment ?? adjustments.first);
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

  Widget _errorStatus(EditorState s) => TextButton(
      onPressed: () {
        if (s.saveError != null) _controller.retrySave();
        if (s.error != null) {
          if (s.gpuSession != null || ref.read(gpuEditorProvider) != null) {
            _controller.recoverPreview();
          } else {
            _controller.regrade();
          }
        }
      },
      child: Text(s.saveError ?? s.error ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: context.palette.danger)));

  Widget _workspace(EditorState s, {required bool overlayCurve}) {
    final tool = _tool;
    final panel =
        s.layout == null || (tool == EditorTool.curves && overlayCurve)
            ? const SizedBox.shrink()
            : tool == null
                ? _tab == 0
                    ? _studioPresets(s)
                    : EditorTools(
                        key: const ValueKey('editor-tools'),
                        onSelected: _open,
                        changed: (t) => _changed(t, s))
                : _panel(tool, s);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (s.layout != null && (s.saveError != null || s.error != null))
        _errorStatus(s),
      Flexible(
        child: tool == EditorTool.curves && !overlayCurve
            ? panel
            : SingleChildScrollView(
                key: ValueKey((tool, tool == null ? _tab : null)),
                child: panel,
              ),
      ),
      if (tool == null && !_presetDraft) _mainNavigation(s) else _confirmBar(s),
    ]);
  }

  Widget _confirmAction(String label, IconData icon, VoidCallback onTap,
          {String? tooltip, bool selected = false}) =>
      Tooltip(
          message: tooltip ?? label,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minWidth: 46, minHeight: 44),
              decoration: BoxDecoration(
                color: selected ? context.palette.divider : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(height: 3),
                    Text(label,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 11, height: 1)),
                  ]),
            ),
          ));

  Widget _confirmBar(EditorState s) {
    final tool = _tool;
    final crop = s.recipe.edits.crop;
    void updateCrop(CropEdit value) {
      _controller.beginGesture();
      _controller.setEdits(ref
          .read(editorProvider(widget.mediaId))
          .recipe
          .edits
          .copyWith(crop: value));
      _controller.endGesture();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(7, 0, 7, 5),
      child: SizedBox(
          height: 49,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _headerButton('取消调整', Icons.close, () => _finish(cancel: true)),
              if (_presetDraft)
                _confirmAction('强度', Icons.tune, () {
                  setState(() => _presetStrength = !_presetStrength);
                }, selected: _presetStrength)
              else if (tool != EditorTool.processVersion)
                _confirmAction('重置', Icons.restart_alt, _resetTool,
                    tooltip: '重置当前工具'),
              if (tool == EditorTool.crop) ...[
                PopupMenuButton<String>(
                  tooltip: '翻转',
                  onSelected: (axis) => updateCrop(axis == '水平翻转'
                      ? crop.copyWith(flipX: !crop.flipX)
                      : crop.copyWith(flipY: !crop.flipY)),
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem(
                        value: '水平翻转',
                        checked: crop.flipX,
                        child: const Text('水平翻转')),
                    CheckedPopupMenuItem(
                        value: '垂直翻转',
                        checked: crop.flipY,
                        child: const Text('垂直翻转')),
                  ],
                  child: const SizedBox(
                    width: 46,
                    height: 44,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.flip, size: 20),
                        SizedBox(height: 3),
                        Text('翻转',
                            maxLines: 1,
                            style: TextStyle(fontSize: 11, height: 1)),
                      ],
                    ),
                  ),
                ),
                _confirmAction('旋转', Icons.rotate_right,
                    () => updateCrop(rotateCrop(crop)),
                    tooltip: '向右旋转90°'),
              ],
              _headerButton('完成调整', Icons.check, _finish),
            ],
          )),
    );
  }

  Widget _curve(EditorState s, {required bool overlay}) => CurvePanel(
      edits: s.recipe.edits,
      histogramSource: s.graded,
      histogramBins: s.histogram,
      overlay: overlay,
      showOriginal: _showOriginal,
      onChanged: _controller.setEdits,
      onStart: _controller.beginGesture,
      onEnd: _controller.endGesture);

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
            activeAdjustment: _activeAdjustment,
            onOpenParameters: () =>
                setState(() => _parametersOpen = !_parametersOpen),
            onStart: _controller.beginGesture,
            onEnd: _controller.endGesture)
      ]);
    }
    switch (tool) {
      case EditorTool.processVersion:
        return SizedBox(
            height: 220,
            child: ChoicePanel<int>(
                values: const [1, 2],
                selected: s.recipe.edits.processVersion,
                label: (v) => v == 1 ? '原有调色' : '新版调色',
                onSelected: (v) => _controller.setEdits(ref
                    .read(editorProvider(widget.mediaId))
                    .recipe
                    .edits
                    .copyWith(processVersion: v)),
                note: '保留现有参数，确认后可撤销'));
      case EditorTool.curves:
        return _curve(s, overlay: false);
      case EditorTool.crop:
        return CropPanel(
            crop: s.recipe.edits.crop,
            showTransforms: false,
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
    if (action == '全部样式') {
      await _showStyleLibrary();
      return;
    }
    if (action == '导入 LUT') {
      await _importLut();
      return;
    }
    if (action == '我的预设') {
      await _presets();
      return;
    }
    if (action == '样式强度') {
      _controller.beginTool();
      setState(() {
        _presetDraft = true;
        _presetStrength = true;
      });
      return;
    }
    if (action == '新版调色') {
      _open(EditorTool.processVersion);
      return;
    }
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
                          if (action == '信息' && s.item != null)
                            Expanded(
                                child: Text(s.item!.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis))
                          else
                            Text(action),
                          if (action != '信息' || s.item == null) const Spacer(),
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

  Future<void> _showStyleLibrary() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * .75,
            ),
            child: Consumer(builder: (context, ref, _) {
              final s = ref.watch(editorProvider(widget.mediaId));
              return SingleChildScrollView(
                child: LutPicker(
                  grid: true,
                  showStrength: false,
                  source: s.base,
                  gpuSession: s.gpuSession,
                  edits: s.recipe.edits,
                  entries: s.luts,
                  selected: s.recipe.lutId,
                  strength: s.recipe.strength,
                  onSelected: (id) {
                    Navigator.of(sheetContext).pop();
                    _selectPreset(id);
                  },
                  onStrength: _controller.setStrength,
                  onStart: _controller.beginGesture,
                  onEnd: _controller.endGesture,
                  onImport: () {
                    Navigator.of(sheetContext).pop();
                    _importLut();
                  },
                ),
              );
            }),
          ),
        ),
      );

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
