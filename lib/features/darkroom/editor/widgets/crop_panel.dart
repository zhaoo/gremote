import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../darkroom/model/photo_edits.dart';
import '../../../../app/widgets/workspace_motion.dart';

class CropPanel extends StatefulWidget {
  const CropPanel(
      {required this.crop,
      required this.sourceWidth,
      required this.sourceHeight,
      required this.onChanged,
      required this.onStart,
      required this.onEnd,
      super.key});
  final CropEdit crop;
  final int sourceWidth, sourceHeight;
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
      '4:3': 4 / 3,
      '3:4': 3 / 4,
      '3:2': 3 / 2,
      '2:3': 2 / 3,
      '16:9': 16 / 9,
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
    return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final ratio in ratios.entries)
                  ChoiceChip(
                      label: Text(ratio.key),
                      selected: selected == ratio.key,
                      onSelected: (_) => _ratio(ratio.key, ratio.value),
                      showCheckmark: false,
                      labelStyle: TextStyle(
                          fontSize: 12,
                          color: selected == ratio.key
                              ? Colors.black
                              : Colors.white70),
                      selectedColor: Colors.white,
                      backgroundColor: const Color(0xff292929),
                      visualDensity: VisualDensity.compact,
                      chipAnimationStyle: ChipAnimationStyle(
                          selectAnimation: AnimationStyle(
                              duration:
                                  WorkspaceMotion.duration(context, 130)))),
              ]),
          const SizedBox(height: 8),
          Wrap(spacing: 12, alignment: WrapAlignment.center, children: [
            IconButton(
                tooltip: '向右旋转90°',
                icon: const Icon(Icons.rotate_90_degrees_cw),
                onPressed: () {
                  setState(() => _selected = '自由');
                  _apply(c.copyWith(
                      quarterTurns: c.quarterTurns + 1,
                      left: 0,
                      top: 0,
                      width: 1,
                      height: 1,
                      aspectRatio: 0));
                }),
            IconButton(
                tooltip: '水平翻转',
                isSelected: c.flipX,
                icon: const Icon(Icons.flip),
                onPressed: () => _apply(c.copyWith(flipX: !c.flipX))),
            IconButton(
                tooltip: '垂直翻转',
                isSelected: c.flipY,
                icon:
                    const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)),
                onPressed: () => _apply(c.copyWith(flipY: !c.flipY))),
          ]),
          Text('校正  ${c.angle > 0 ? '+' : ''}${c.angle.toStringAsFixed(1)}°',
              style: const TextStyle(fontSize: 13, color: Colors.white70)),
          Slider(
              value: c.angle,
              min: -45,
              max: 45,
              label: '${c.angle.toStringAsFixed(1)}°',
              activeColor: Colors.white,
              semanticFormatterCallback: (v) => '${v.toStringAsFixed(1)}度',
              onChangeStart: (_) => widget.onStart(),
              onChanged: (v) => widget.onChanged(c.copyWith(angle: v)),
              onChangeEnd: (_) => widget.onEnd()),
        ]));
  }
}

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
              IgnorePointer(child: CustomPaint(painter: _CropPainter(rect))),
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
  const _CropPainter(this.rect);
  final Rect rect;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addRect(rect),
        Paint()..color = Colors.black45);
    final line = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(rect, line);
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
          Offset(rect.left + rect.width * i / 3, rect.top),
          Offset(rect.left + rect.width * i / 3, rect.bottom),
          line..color = Colors.white38);
      canvas.drawLine(Offset(rect.left, rect.top + rect.height * i / 3),
          Offset(rect.right, rect.top + rect.height * i / 3), line);
    }
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
  bool shouldRepaint(_CropPainter oldDelegate) => oldDelegate.rect != rect;
}
