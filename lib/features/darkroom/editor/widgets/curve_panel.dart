import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../app/theme/app_palette.dart';
import 'package:flutter/gestures.dart';
import '../../../../darkroom/model/photo_edits.dart';
import '../../../../app/widgets/workspace_motion.dart';
import '../../../../imaging/imaging_engine.dart';

class CurvePanel extends StatefulWidget {
  const CurvePanel(
      {required this.edits,
      required this.onChanged,
      required this.onStart,
      required this.onEnd,
      this.histogramSource,
      super.key});
  final PhotoEdits edits;
  final ValueChanged<PhotoEdits> onChanged;
  final VoidCallback onStart, onEnd;
  final PreviewImage? histogramSource;
  @override
  State<CurvePanel> createState() => _CurvePanelState();
}

class _CurvePanelState extends State<CurvePanel> {
  int _channel = 0;
  int? _selected;
  bool _dragging = false;
  List<List<double>>? _histogram;
  static const _names = ['RGB', 'R', 'G', 'B'];
  static const _colors = [
    Colors.white,
    Color(0xfff18a87),
    Color(0xff94d4a0),
    Color(0xff88aff2)
  ];
  Color _channelColor(BuildContext context, int channel) {
    if (channel == 0) return context.palette.text;
    const light = [
      Color(0xff222725),
      Color(0xff9c4138),
      Color(0xff437453),
      Color(0xff456b91)
    ];
    return Theme.of(context).brightness == Brightness.light
        ? light[channel]
        : _colors[channel];
  }

  ToneCurve get _curve => widget.edits.curves[_channel];
  @override
  void initState() {
    super.initState();
    _readHistogram();
  }

  @override
  void didUpdateWidget(CurvePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.histogramSource != widget.histogramSource) _readHistogram();
  }

  void _readHistogram() {
    final source = widget.histogramSource;
    if (source == null || source.rgba.length < 4) {
      _histogram = null;
      return;
    }
    final bins = List.generate(4, (_) => List<double>.filled(64, 0));
    // Bound work to 65k samples; counts always come from actual preview pixels.
    final count =
        math.min(source.width * source.height, source.rgba.length ~/ 4);
    final stride = math.max(1, (count / 65536).ceil());
    for (var i = 0; i < count; i += stride) {
      final p = i * 4;
      if (source.rgba[p + 3] == 0) continue;
      final r = source.rgba[p], g = source.rgba[p + 1], b = source.rgba[p + 2];
      bins[0][((r * .2126 + g * .7152 + b * .0722) / 4).floor().clamp(0, 63)]++;
      bins[1][r ~/ 4]++;
      bins[2][g ~/ 4]++;
      bins[3][b ~/ 4]++;
    }
    _histogram = bins;
  }

  void _set(ToneCurve curve) =>
      widget.onChanged(widget.edits.withCurve(_channel, curve));
  void _transaction(ToneCurve curve) {
    widget.onStart();
    _set(curve);
    widget.onEnd();
  }

  Rect _plot(Size size) => Rect.fromLTWH(
      16, 16, math.max(1, size.width - 32), math.max(1, size.height - 32));
  Offset _position(CurvePoint p, Rect r) =>
      Offset(r.left + p.x * r.width, r.bottom - p.y * r.height);
  int? _nearest(Offset position, Rect r) {
    double distance = 26;
    int? index;
    for (var i = 0; i < _curve.points.length; i++) {
      final d = (_position(_curve.points[i], r) - position).distance;
      if (d < distance) {
        distance = d;
        index = i;
      }
    }
    return index;
  }

  void _begin(Offset position, Size size, {required bool drag}) {
    final rect = _plot(size);
    var index = _nearest(position, rect);
    if (index == null && _curve.points.length >= 32) return;
    if (drag) {
      widget.onStart();
      _dragging = true;
    }
    if (index == null) {
      final x = ((position.dx - rect.left) / rect.width).clamp(.001, .999);
      // Keep a small separation so Hermite intervals remain well conditioned.
      if (_curve.points.any((p) => (p.x - x).abs() < .005)) return;
      final points = [
        ..._curve.points,
        CurvePoint(x, ((rect.bottom - position.dy) / rect.height).clamp(0, 1))
      ]..sort((a, b) => a.x.compareTo(b.x));
      index = points.indexWhere((p) => p.x == x);
      if (!drag) widget.onStart();
      _set(ToneCurve.fromPoints(points));
      if (!drag) widget.onEnd();
    }
    setState(() => _selected = index);
  }

  void _move(Offset position, Size size) {
    final index = _selected;
    if (index == null || index >= _curve.points.length) return;
    final rect = _plot(size), points = [..._curve.points];
    final x = index == 0
        ? 0.0
        : index == points.length - 1
            ? 1.0
            : ((position.dx - rect.left) / rect.width)
                .clamp(points[index - 1].x + .001, points[index + 1].x - .001);
    points[index] =
        CurvePoint(x, ((rect.bottom - position.dy) / rect.height).clamp(0, 1));
    _set(ToneCurve.fromPoints(points));
  }

  void _end() {
    if (_dragging) {
      _dragging = false;
      widget.onEnd();
    }
  }

  void _nudge(double amount) {
    final index = _selected;
    if (index == null || index >= _curve.points.length) return;
    final points = [..._curve.points], p = _curve.points[index];
    points[index] = CurvePoint(p.x, (p.y + amount).clamp(0, 1));
    _transaction(ToneCurve.fromPoints(points));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final removable =
        selected != null && selected > 0 && selected < _curve.points.length - 1;
    return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  ChoiceChip(
                      label: Text(_names[i]),
                      selected: i == _channel,
                      showCheckmark: false,
                      chipAnimationStyle: ChipAnimationStyle(
                          selectAnimation: AnimationStyle(
                              duration:
                                  WorkspaceMotion.duration(context, 130))),
                      selectedColor: _channelColor(context, i),
                      backgroundColor: context.palette.raised,
                      labelStyle: TextStyle(
                          color: i == _channel
                              ? (_channelColor(context, i).computeLuminance() >
                                      .179
                                  ? Colors.black
                                  : Colors.white)
                              : _channelColor(context, i),
                          fontSize: 12),
                      onSelected: (_) => setState(() {
                            _channel = i;
                            _selected = null;
                          }))
              ]),
          const SizedBox(height: 8),
          AspectRatio(
              aspectRatio: 1.9,
              child: LayoutBuilder(builder: (context, constraints) {
                final size = constraints.biggest;
                return Semantics(
                    increasedValue: selected == null ? null : '提高输出',
                    decreasedValue: selected == null ? null : '降低输出',
                    label: '${_names[_channel]}曲线，点击添加控制点，拖动调整',
                    value: selected != null && selected < _curve.points.length
                        ? '输入${(_curve.points[selected].x * 255).round()}，输出${(_curve.points[selected].y * 255).round()}'
                        : null,
                    onIncrease: selected == null ? null : () => _nudge(.02),
                    onDecrease: selected == null ? null : () => _nudge(-.02),
                    child: GestureDetector(
                        key: const ValueKey('curve-graph'),
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onTapUp: (d) =>
                            _begin(d.localPosition, size, drag: false),
                        onPanStart: (d) =>
                            _begin(d.localPosition, size, drag: true),
                        onPanUpdate: (d) => _move(d.localPosition, size),
                        onPanEnd: (_) => _end(),
                        onPanCancel: _end,
                        child: CustomPaint(
                            painter: _CurvePainter(
                                _curve,
                                _channelColor(context, _channel),
                                _selected,
                                _histogram?[_channel],
                                context.palette))));
              })),
          Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                for (final entry in <String, List<CurvePoint>>{
                  '线性': const [CurvePoint(0, 0), CurvePoint(1, 1)],
                  '柔和': const [
                    CurvePoint(0, .06),
                    CurvePoint(.25, .28),
                    CurvePoint(.75, .73),
                    CurvePoint(1, .96)
                  ],
                  '对比': const [
                    CurvePoint(0, 0),
                    CurvePoint(.25, .18),
                    CurvePoint(.75, .82),
                    CurvePoint(1, 1)
                  ]
                }.entries)
                  TextButton(
                      onPressed: () {
                        setState(() => _selected = null);
                        _transaction(ToneCurve.fromPoints(entry.value));
                      },
                      child: Text(entry.key)),
                TextButton(
                    onPressed: removable
                        ? () {
                            final points = [..._curve.points]
                              ..removeAt(selected);
                            setState(() => _selected = null);
                            _transaction(ToneCurve.fromPoints(points));
                          }
                        : null,
                    child: const Text('删除控制点')),
              ]),
          Text('轻点添加 · 拖动控制点',
              style: TextStyle(color: context.palette.muted, fontSize: 11)),
        ]));
  }
}

class _CurvePainter extends CustomPainter {
  const _CurvePainter(
      this.curve, this.color, this.selected, this.histogram, this.palette);
  final AppPalette palette;
  final ToneCurve curve;
  final Color color;
  final int? selected;
  final List<double>? histogram;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(16, 16, size.width - 32, size.height - 32);
    canvas.drawRect(rect, Paint()..color = palette.raised);
    final bins = histogram;
    if (bins != null) {
      final peak = bins.fold<double>(0, math.max);
      if (peak > 0) {
        final path = Path()..moveTo(rect.left, rect.bottom);
        for (var i = 0; i < bins.length; i++) {
          path.lineTo(rect.left + i / (bins.length - 1) * rect.width,
              rect.bottom - math.sqrt(bins[i] / peak) * rect.height * .85);
        }
        path.lineTo(rect.right, rect.bottom);
        path.close();
        canvas.drawPath(path, Paint()..color = color.withOpacity(.14));
      }
    }
    final grid = Paint()
      ..color = palette.divider
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final f = i / 4;
      canvas.drawLine(Offset(rect.left + f * rect.width, rect.top),
          Offset(rect.left + f * rect.width, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, rect.top + f * rect.height),
          Offset(rect.right, rect.top + f * rect.height), grid);
    }
    canvas.drawLine(rect.bottomLeft, rect.topRight, grid);
    final path = Path(), values = curve.samples();
    for (var i = 0; i < values.length; i++) {
      final x = rect.left + i / 255 * rect.width,
          y = rect.bottom - values[i] * rect.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    for (var i = 0; i < curve.points.length; i++) {
      final p = curve.points[i],
          offset = Offset(
              rect.left + p.x * rect.width, rect.bottom - p.y * rect.height);
      canvas.drawCircle(offset, i == selected ? 7 : 5, Paint()..color = color);
      canvas.drawCircle(offset, 2.5, Paint()..color = palette.raised);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.curve != curve ||
      oldDelegate.color != color ||
      oldDelegate.selected != selected ||
      oldDelegate.histogram != histogram;
}
