import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../darkroom/darkroom_providers.dart';
import '../../../../darkroom/frame/frame_layout.dart';
import '../../../../darkroom/lut/lut_library.dart';
import '../../../../darkroom/model/export_recipe.dart';
import '../../../../darkroom/model/photo_edits.dart';
import '../../../../imaging/imaging_engine.dart';
import '../../../../imaging/gpu/gpu_editor.dart';
import 'frame_preview.dart';

/// Current-photo LUT thumbnails, rendered serially by the shared native engine.
class LutPicker extends ConsumerStatefulWidget {
  const LutPicker({
    required this.source,
    this.gpuSession,
    this.grid = false,
    this.showStrength = true,
    this.onStrengthTap,
    this.onSchemes,
    required this.edits,
    required this.entries,
    required this.selected,
    required this.strength,
    required this.onSelected,
    required this.onStrength,
    required this.onStart,
    required this.onEnd,
    required this.onImport,
    super.key,
  });

  final PreviewImage? source;
  final GpuEditorSession? gpuSession;
  final bool grid, showStrength;
  final VoidCallback? onStrengthTap, onSchemes;
  final PhotoEdits edits;
  final List<LutEntry> entries;
  final String? selected;
  final double strength;
  final ValueChanged<String?> onSelected;
  final ValueChanged<double> onStrength;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final VoidCallback onImport;

  @override
  ConsumerState<LutPicker> createState() => _LutPickerState();
}

class _ThumbnailRequest {
  _ThumbnailRequest(this.id, this.generation);
  final String? id;
  final int generation;
  final result = Completer<PreviewImage?>();
}

class _LutPickerState extends ConsumerState<LutPicker> {
  String _collection = "全部";
  List<String> _recent = [];
  Set<String> _favorites = {};
  @override
  void initState() {
    super.initState();
    if (widget.grid) _loadCollections();
  }

  Future<void> _loadCollections() async {
    try {
      final (recent, favorites) =
          await ref.read(darkroomStoreProvider).lutCollections();
      if (mounted) {
        setState(() {
          _recent = recent;
          _favorites = favorites;
        });
      }
    } catch (_) {
      /* Report a failed write if the user attempts to change a collection. */
    }
  }

  Future<void> _favorite() async {
    final id = widget.selected;
    if (id == null) return;
    try {
      await ref.read(darkroomStoreProvider).toggleLutFavorite(id);
      await _loadCollections();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("收藏未保存，请重试")));
      }
    }
  }

  final _cache = <String?, Future<PreviewImage?>>{};
  final _queue = Queue<_ThumbnailRequest>();
  int _generation = 0;
  bool _working = false;
  _ThumbnailRequest? _active;

  @override
  void didUpdateWidget(LutPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gpuSession != widget.gpuSession ||
        oldWidget.source != widget.source ||
        oldWidget.edits != widget.edits ||
        (!widget.grid && oldWidget.strength != widget.strength)) {
      _invalidate();
    }
  }

  void _invalidate() {
    _generation++;
    _cache.clear();
    for (final request in _queue) {
      if (!request.result.isCompleted) request.result.complete(null);
    }
    _queue.clear();
    final active = _active;
    if (active != null && !active.result.isCompleted) {
      active.result.complete(null);
    }
  }

  @override
  void dispose() {
    _invalidate();
    super.dispose();
  }

  Future<PreviewImage?> _thumbnail(String? id) {
    if (widget.source == null && widget.gpuSession == null) {
      return Future.value(null);
    }
    final existing = _cache.remove(id);
    if (existing != null) {
      _cache[id] = existing;
      return existing;
    }
    final request = _ThumbnailRequest(id, _generation);
    _cache[id] = request.result.future;
    // Only future handles and at most twelve small RGBA buffers are retained.
    // An evicted visible tile keeps its own future until it leaves the list.
    while (_cache.length > 12) {
      _cache.remove(_cache.keys.first);
    }
    _queue.add(request);
    scheduleMicrotask(_drain);
    return request.result.future;
  }

  Future<void> _drain() async {
    if (_working || !mounted || _queue.isEmpty) return;
    _working = true;
    final request = _active = _queue.removeFirst();
    final source = widget.source;
    final edits = widget.edits;
    final strength = widget.grid ? 1.0 : widget.strength;
    final engine = ref.read(imagingEngineProvider);
    final library = ref.read(lutLibraryProvider);
    try {
      if (widget.gpuSession != null) {
        final cube =
            request.id == null ? null : await library.load(request.id!);
        if (!mounted || request.generation != _generation) return;
        final image = await widget.gpuSession!.thumbnail(edits, cube, strength);
        if (mounted &&
            request.generation == _generation &&
            !request.result.isCompleted) request.result.complete(image);
      } else if (source != null) {
        final (cropWidth, cropHeight) =
            edits.crop.outputSize(source.width, source.height);
        final scale = math.min(1.0, 96 / math.max(cropWidth, cropHeight));
        final cube =
            request.id == null ? null : await library.load(request.id!);
        if (!mounted || request.generation != _generation) return;
        final image = await engine.renderPhoto(
          source,
          adjustments: edits.nativeParameters,
          cube: cube,
          strength: strength,
          width: math.max(1, (cropWidth * scale).round()),
          height: math.max(1, (cropHeight * scale).round()),
        );
        if (mounted &&
            request.generation == _generation &&
            !request.result.isCompleted) {
          request.result.complete(image);
        }
      }
    } catch (_) {
      // A missing or malformed LUT keeps its selectable placeholder. Import
      // and the full-size editor expose the actionable error in their flows.
    } finally {
      if (!request.result.isCompleted) request.result.complete(null);
      _active = null;
      _working = false;
      if (mounted && _queue.isNotEmpty) scheduleMicrotask(_drain);
    }
  }

  Widget _tile(LutEntry? entry, {bool grid = false}) {
    final id = entry?.id;
    final selected = widget.selected == id;
    return SizedBox(
      width: grid ? null : 82,
      child: Semantics(
        button: true,
        selected: selected,
        label: entry?.name ?? '原图',
        child: InkWell(
          key: ValueKey(id == null ? 'lut-original' : 'lut-$id'),
          onTap: () => widget.onSelected(id),
          borderRadius: BorderRadius.circular(grid ? 2 : 10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(children: [
              Container(
                height: grid ? 86 : 76,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: context.palette.raised,
                  borderRadius: BorderRadius.circular(grid ? 1 : 9),
                  border: Border.all(
                    color: selected
                        ? context.palette.text
                        : context.palette.divider,
                    width: selected ? 1 : .5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(grid ? 0 : 5),
                  child: FutureBuilder<PreviewImage?>(
                    key: ValueKey((_generation, id)),
                    future: _thumbnail(id),
                    builder: (context, snapshot) {
                      final image = snapshot.data;
                      if (image == null) {
                        return Center(
                            child: Icon(
                          Icons.image_outlined,
                          size: 20,
                          color: context.palette.muted,
                        ));
                      }
                      final preview = FramePreview(
                        layout: computeFrameLayout(
                          photoWidth: image.width,
                          photoHeight: image.height,
                          style: FrameStyle.none,
                          ratio: FrameRatio.original,
                          content: const FrameContent(),
                        ),
                        image: image,
                      );
                      return grid
                          ? ClipRect(
                              child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                      width: image.width.toDouble(),
                                      height: image.height.toDouble(),
                                      child: preview)))
                          : preview;
                    },
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                entry?.name ?? '原图',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    color: selected
                        ? context.palette.text
                        : context.palette.muted),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _grid() {
    final all = <LutEntry?>[null, ...widget.entries];
    final entries = all
        .where((e) =>
            _collection == '全部' ||
            (e != null &&
                (_collection == '最近'
                    ? _recent.contains(e.id)
                    : _favorites.contains(e.id))))
        .toList();
    if (_collection == '最近') {
      entries.sort(
          (a, b) => _recent.indexOf(a!.id).compareTo(_recent.indexOf(b!.id)));
    }
    final name = widget.entries
            .where((e) => e.id == widget.selected)
            .firstOrNull
            ?.name ??
        '原图';
    if (widget.showStrength && widget.selected != null) {
      return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                  child: TextButton.icon(
                      onPressed: widget.onStrengthTap,
                      style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.zero),
                      icon: const Icon(Icons.chevron_left, size: 18),
                      label: Text(name,
                          maxLines: 1, overflow: TextOverflow.ellipsis))),
              IconButton(
                  tooltip:
                      _favorites.contains(widget.selected) ? '取消收藏' : '收藏预设',
                  onPressed: _favorite,
                  icon: Icon(
                      _favorites.contains(widget.selected)
                          ? Icons.bookmark
                          : Icons.bookmark_outline,
                      size: 18))
            ]),
            const SizedBox(height: 16),
            Text('${(widget.strength * 100).round()}%',
                style: const TextStyle(
                    fontSize: 30,
                    fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(height: 12),
            SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 1.2),
                child: Slider(
                    key: const ValueKey('lut-strength'),
                    value: widget.strength.clamp(0, 1),
                    onChangeStart: (_) => widget.onStart(),
                    onChanged: widget.onStrength,
                    onChangeEnd: (_) => widget.onEnd())),
          ]));
    }
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            for (final title in ['全部', '最近', '收藏'])
              TextButton(
                  onPressed: () => setState(() => _collection = title),
                  style: TextButton.styleFrom(
                      foregroundColor: _collection == title
                          ? context.palette.text
                          : context.palette.muted,
                      minimumSize: const Size(48, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: Text(title, style: const TextStyle(fontSize: 12))),
            const Spacer(),
            IconButton(
                key: const ValueKey('lut-import'),
                tooltip: '导入 LUT',
                onPressed: widget.onImport,
                icon: const Icon(Icons.add, size: 21))
          ]),
          if (entries.isEmpty)
            Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_collection == '收藏' ? '尚无收藏' : '尚无最近使用',
                    style:
                        TextStyle(color: context.palette.muted, fontSize: 12))),
          GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 123),
              itemCount: entries.length,
              itemBuilder: (_, i) => _tile(entries[i], grid: true)),
          Row(children: [
            Expanded(
                child: TextButton(
                    onPressed:
                        widget.selected == null ? null : widget.onStrengthTap,
                    style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.zero),
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)))),
            if (widget.selected != null)
              IconButton(
                  tooltip:
                      _favorites.contains(widget.selected) ? '取消收藏' : '收藏预设',
                  onPressed: _favorite,
                  icon: Icon(
                      _favorites.contains(widget.selected)
                          ? Icons.bookmark
                          : Icons.bookmark_outline,
                      size: 18)),
            TextButton(
                onPressed:
                    widget.selected == null ? null : widget.onStrengthTap,
                child: Text('${(widget.strength * 100).round()}%',
                    style: const TextStyle(fontSize: 12))),
            if (widget.onSchemes != null)
              IconButton(
                  tooltip: '我的方案',
                  onPressed: widget.onSchemes,
                  icon: const Icon(Icons.layers_outlined, size: 18)),
          ]),
          if (widget.showStrength)
            Slider(
                key: const ValueKey('lut-strength'),
                value: widget.strength.clamp(0, 1),
                onChangeStart: (_) => widget.onStart(),
                onChanged: widget.onStrength,
                onChangeEnd: (_) => widget.onEnd()),
        ]));
  }

  @override
  Widget build(BuildContext context) => widget.grid
      ? _grid()
      : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Row(children: [
                const Expanded(
                    child: Text('滤镜', style: TextStyle(fontSize: 13))),
                IconButton(
                  key: const ValueKey('lut-import'),
                  tooltip: '导入 LUT',
                  onPressed: widget.onImport,
                  icon: const Icon(Icons.add_rounded, size: 21),
                ),
              ]),
            ),
            SizedBox(
              height: 114,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                addAutomaticKeepAlives: false,
                itemCount: widget.entries.length + 1,
                itemBuilder: (context, index) {
                  final entry = index == 0 ? null : widget.entries[index - 1];
                  return _tile(entry);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Text('强度',
                    style:
                        TextStyle(fontSize: 12, color: context.palette.muted)),
                Expanded(
                    child: Slider(
                  key: const ValueKey('lut-strength'),
                  value: widget.strength.clamp(0, 1),
                  semanticFormatterCallback: (value) =>
                      '${(value * 100).round()}%',
                  onChangeStart: (_) => widget.onStart(),
                  onChanged: widget.onStrength,
                  onChangeEnd: (_) => widget.onEnd(),
                )),
                SizedBox(
                    width: 34,
                    child: Text('${(widget.strength * 100).round()}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12, color: context.palette.muted))),
              ]),
            ),
          ],
        );
}
