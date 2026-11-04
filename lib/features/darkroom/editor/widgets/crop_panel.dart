import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../darkroom/model/photo_edits.dart';
import 'editor_ruler.dart';

class CropPanel extends StatefulWidget {
  const CropPanel(
      {required this.crop,
      required this.sourceWidth,
      required this.sourceHeight,
      required this.onChanged,
      required this.onStart,
      required this.onEnd,
      this.showTransforms = true,
      super.key});
  final CropEdit crop;
  final int sourceWidth, sourceHeight;
  final bool showTransforms;
  final ValueChanged<CropEdit> onChanged;
  final VoidCallback onStart, onEnd;
  @override
  State<CropPanel> createState() => _CropPanelState();
}

class _CropPanelState extends State<CropPanel> {
  String _selected = '自由';
  void _apply(CropEdit crop) {
    widget.onStart();
    widget.onChanged(crop);
    widget.onEnd();
  }

  void _ratio(String label, double? ratio) {
    setState(() => _selected = label);
    final c = widget.crop;
    if (ratio == null) {
      _apply(c.copyWith(aspectRatio: 0));
      return;
    }
    final w = math.max(
        1, c.quarterTurns.isOdd ? widget.sourceHeight : widget.sourceWidth);
    final h = math.max(
        1, c.quarterTurns.isOdd ? widget.sourceWidth : widget.sourceHeight);
    final relative = ratio / (w / h);
    final width = math.min(1.0, relative), height = math.min(1.0, 1 / relative);
    _apply(c.copyWith(
        left: (1 - width) / 2,
        top: (1 - height) / 2,
        width: width,
        height: height,
        aspectRatio: ratio));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.crop;
    final ratios = <String, double?>{
      '自由': null,
      '原始': c.quarterTurns.isOdd
          ? widget.sourceHeight / math.max(1, widget.sourceWidth)
          : widget.sourceWidth / math.max(1, widget.sourceHeight),
      '1:1': 1,
      '3:2': 3 / 2,
      '4:3': 4 / 3,
      '16:9': 16 / 9,
      '3:4': 3 / 4,
      '2:3': 2 / 3,
      '9:16': 9 / 16
    };
    final selected = c.aspectRatio == 0
        ? '自由'
        : ratios[_selected] != null &&
                (ratios[_selected]! - c.aspectRatio).abs() < .0001
            ? _selected
            : ratios.entries
                .where((e) =>
                    e.value != null && (e.value! - c.aspectRatio).abs() < .0001)
                .map((e) => e.key)
                .firstOrNull;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          SizedBox(
            height: 38,
            child: Stack(alignment: Alignment.center, children: [
              const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('角度', style: TextStyle(fontSize: 13))),
              Text('${c.angle.toStringAsFixed(2)}°',
                  style: const TextStyle(
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ]),
          ),
          EditorRuler(
            value: c.angle,
            min: -45,
            max: 45,
            format: (v) => '${v.toStringAsFixed(2)}度',
            onStart: widget.onStart,
            onEnd: widget.onEnd,
            onChanged: (v) => widget.onChanged(widget.crop.copyWith(angle: v)),
          ),
        ]),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(children: [
          for (final ratio in ratios.entries)
            Semantics(
              button: true,
              selected: selected == ratio.key,
              child: InkWell(
                onTap: () => _ratio(ratio.key, ratio.value),
                child: SizedBox(
                    width: 65,
                    height: 70,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 42,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                                color: selected == ratio.key
                                    ? context.palette.text
                                    : Colors.transparent),
                          ),
                          child: switch (ratio.key) {
                            '自由' => const Icon(Icons.crop_free, size: 21),
                            '原始' => const Icon(Icons.image_outlined, size: 21),
                            _ => Container(
                                width: 20 * math.min(1.0, ratio.value!),
                                height: 20 / math.max(1.0, ratio.value!),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  border: Border.all(
                                      color: context.palette.text, width: 1.7),
                                ),
                              ),
                          },
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.showTransforms
                              ? ratio.key
                              : switch (ratio.key) {
                                  '1:1' => '正方形',
                                  '原始' => '原图',
                                  _ => ratio.key,
                                },
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, height: 1),
                        ),
                      ],
                    )),
              ),
            ),
        ]),
      ),
      if (widget.showTransforms)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
              tooltip: '向右旋转90°',
              icon: const Icon(Icons.rotate_right),
              onPressed: () => _apply(rotateCrop(c))),
          IconButton(
              tooltip: '水平翻转',
              isSelected: c.flipX,
              icon: const Icon(Icons.flip),
              onPressed: () => _apply(c.copyWith(flipX: !c.flipX))),
          IconButton(
              tooltip: '垂直翻转',
              isSelected: c.flipY,
              icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)),
              onPressed: () => _apply(c.copyWith(flipY: !c.flipY))),
        ]),
    ]);
  }
}

CropEdit rotateCrop(CropEdit crop) => crop.copyWith(
      quarterTurns: crop.quarterTurns + 1,
      left: 0,
      top: 0,
      width: 1,
      height: 1,
      aspectRatio: 0,
    );

/// Positioned over the uncropped, rotated image. Coordinates stay normalized.
class CropSelection extends StatefulWidget {
  const CropSelection(
      {required this.child,
      required this.crop,
      required this.onChanged,
      required this.onStart,
      required this.onEnd,
      super.key});
  final Widget child;
  final CropEdit crop;
  final ValueChanged<CropEdit> onChanged;
  final VoidCallback onStart, onEnd;
  @override
  State<CropSelection> createState() => _CropSelectionState();
}

class _CropSelectionState extends State<CropSelection> {
  CropEdit? _start;
  Offset _delta = Offset.zero;
  void _begin() {
    _start = widget.crop;
    _delta = Offset.zero;
    widget.onStart();
  }

  void _end() {
    if (_start == null) return;
    _start = null;
    widget.onEnd();
  }

  void _drag(DragUpdateDetails details, Size size, int? corner) {
    final c = _start;
    if (c == null || size.isEmpty) return;
    _delta += details.delta;
    final dx = _delta.dx / size.width, dy = _delta.dy / size.height;
    if (corner == null) {
      widget.onChanged(c.copyWith(
          left: (c.left + dx).clamp(0, 1 - c.width),
          top: (c.top + dy).clamp(0, 1 - c.height)));
      return;
    }
    final minW = math.min(1.0, 24 / size.width),
        minH = math.min(1.0, 24 / size.height);
    if (c.aspectRatio > 0) {
      final leftSide = corner == 0 || corner == 3;
      final topSide = corner == 0 || corner == 1;
      final ratio = c.width / c.height;
      final anchorX = leftSide ? c.left + c.width : c.left;
      final anchorY = topSide ? c.top + c.height : c.top;
      final availableW = leftSide ? anchorX : 1 - anchorX;
      final availableH = topSide ? anchorY : 1 - anchorY;
      final maxWidth = math.min(availableW, availableH * ratio);
      final minWidth = math.min(maxWidth, math.max(minW, minH * ratio));
      final proposedWidth = (dx / c.width).abs() >= (dy / c.height).abs()
          ? c.width + (leftSide ? -dx : dx)
          : (c.height + (topSide ? -dy : dy)) * ratio;
      final width = proposedWidth.clamp(minWidth, maxWidth);
      final height = width / ratio;
      widget.onChanged(c.copyWith(
          left: leftSide ? anchorX - width : anchorX,
          top: topSide ? anchorY - height : anchorY,
          width: width,
          height: height));
      return;
    }
    var l = c.left, t = c.top, r = c.left + c.width, b = c.top + c.height;
    if (corner == 0 || corner == 3) {
      l = (l + dx).clamp(0, math.max(0, r - minW));
    } else {
      r = (r + dx).clamp(math.min(1, l + minW), 1);
    }
    if (corner == 0 || corner == 1) {
      t = (t + dy).clamp(0, math.max(0, b - minH));
    } else {
      b = (b + dy).clamp(math.min(1, t + minH), 1);
    }
    widget.onChanged(c.copyWith(left: l, top: t, width: r - l, height: b - t));
  }

  Widget _gesture(Size size, int? corner, Widget child) => GestureDetector(
      key: ValueKey(corner == null ? 'crop-move' : 'crop-handle-$corner'),
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _begin(),
      onPanUpdate: (d) => _drag(d, size, corner),
      onPanEnd: (_) => _end(),
      onPanCancel: _end,
      child: child);
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest, c = widget.crop;
        final rect = Rect.fromLTWH(c.left * size.width, c.top * size.height,
            c.width * size.width, c.height * size.height);
        return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              widget.child,
              IgnorePointer(
                  child: CustomPaint(
                      painter: _CropPainter(
                          rect,
                          Theme.of(context).brightness == Brightness.light
                              ? const Color(0x75e7e7df)
                              : Colors.black45))),
              Positioned.fromRect(
                  rect: rect,
                  child: _gesture(
                      size,
                      null,
                      Semantics(
                          label: '移动裁切区域', child: const SizedBox.expand()))),
              for (var i = 0; i < 4; i++)
                Positioned(
                    left:
                        ([rect.left, rect.right, rect.right, rect.left][i] - 22)
                            .clamp(0.0, math.max(0.0, size.width - 44)),
                    top:
                        ([rect.top, rect.top, rect.bottom, rect.bottom][i] - 22)
                            .clamp(0.0, math.max(0.0, size.height - 44)),
                    width: 44,
                    height: 44,
                    child: _gesture(
                        size,
                        i,
                        Semantics(
                            label: ['调整左上角', '调整右上角', '调整右下角', '调整左下角'][i],
                            child: const SizedBox.expand()))),
            ]);
      });
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.rect, this.shade);
  final Color shade;
  final Rect rect;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addRect(rect),
        Paint()..color = shade);
    final line = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(rect, line);
    line
      ..color = Colors.white
      ..strokeWidth = 3;
    for (final p in [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft
    ]) {
      final x = p.dx == rect.left ? 1 : -1, y = p.dy == rect.top ? 1 : -1;
      canvas.drawLine(p, p + Offset(14.0 * x, 0), line);
      canvas.drawLine(p, p + Offset(0, 14.0 * y), line);
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.shade != shade;
}
