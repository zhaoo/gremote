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
import 'frame_preview.dart';

/// Current-photo LUT thumbnails, rendered serially by the shared native engine.
class LutPicker extends ConsumerStatefulWidget {
  const LutPicker({
    required this.source,
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
  final _cache = <String?, Future<PreviewImage?>>{};
  final _queue = Queue<_ThumbnailRequest>();
  int _generation = 0;
  bool _working = false;
  _ThumbnailRequest? _active;

  @override
  void didUpdateWidget(LutPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.edits != widget.edits ||
        oldWidget.strength != widget.strength) {
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
    if (widget.source == null) return Future.value(null);
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
    final strength = widget.strength;
    final engine = ref.read(imagingEngineProvider);
    final library = ref.read(lutLibraryProvider);
    try {
      if (source != null) {
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

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Row(children: [
              const Expanded(child: Text('滤镜', style: TextStyle(fontSize: 13))),
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
                final id = entry?.id;
                final selected = widget.selected == id;
                return SizedBox(
                  width: 82,
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: entry?.name ?? '原图',
                    child: InkWell(
                      key: ValueKey(id == null ? 'lut-original' : 'lut-$id'),
                      onTap: () => widget.onSelected(id),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(children: [
                          Container(
                            height: 76,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: context.palette.raised,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: selected
                                    ? context.palette.text
                                    : context.palette.divider,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
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
                                  return FramePreview(
                                    layout: computeFrameLayout(
                                      photoWidth: image.width,
                                      photoHeight: image.height,
                                      style: FrameStyle.none,
                                      ratio: FrameRatio.original,
                                      content: const FrameContent(),
                                    ),
                                    image: image,
                                  );
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
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Text('强度',
                  style: TextStyle(fontSize: 12, color: context.palette.muted)),
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
