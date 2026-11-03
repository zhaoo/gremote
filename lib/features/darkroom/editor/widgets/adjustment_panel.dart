import 'package:flutter/material.dart';
import 'precision_dialog.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../darkroom/model/photo_edits.dart';

/// Native parameter controls. A slider gesture is one document transaction.
class AdjustmentPanel extends StatefulWidget {
  const AdjustmentPanel(
      {required this.edits,
      required this.adjustments,
      required this.onChanged,
      required this.onStart,
      required this.onEnd,
      this.onActiveChanged,
      super.key});
  final PhotoEdits edits;
  final List<PhotoAdjustment> adjustments;
  final ValueChanged<PhotoEdits> onChanged;
  final VoidCallback onStart, onEnd;
  final ValueChanged<PhotoAdjustment>? onActiveChanged;
  @override
  State<AdjustmentPanel> createState() => _AdjustmentPanelState();
}

class _AdjustmentPanelState extends State<AdjustmentPanel> {
  PhotoAdjustment? _active;
  void _reset(PhotoAdjustment adjustment) {
    widget.onStart();
    widget.onChanged(widget.edits.withValue(adjustment, adjustment.initial));
    widget.onEnd();
  }

  Future<void> _precise(PhotoAdjustment active) async {
    final factor = active == PhotoAdjustment.exposure ? 1.0 : 100.0;
    final result =
        await showPrecisionDialog(context, title: active.label, fields: [
      PrecisionField('数值', widget.edits.value(active) * factor,
          active.min * factor, active.max * factor,
          key: const ValueKey('precision-input'))
    ]);
    if (!mounted || result == null) return;
    widget.onStart();
    widget.onChanged(widget.edits.withValue(active, result.single / factor));
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.adjustments.isEmpty) return const SizedBox.shrink();
    final active = widget.adjustments.contains(_active)
        ? _active!
        : widget.adjustments.first;
    final value = widget.edits.value(active);
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
              key: const ValueKey('adjustment-value'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _precise(active),
              onDoubleTap: () => _reset(active),
              child: Semantics(
                  label: '${active.label}，${active.display(value)}，双击恢复默认值',
                  excludeSemantics: true,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Center(
                          child: Text(active.display(value),
                              style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w400,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                  color: context.palette.text)))))),
          SizedBox(
              height: 56,
              child: Stack(alignment: Alignment.center, children: [
                Positioned(
                    left: 24,
                    right: 24,
                    top: 8,
                    child: CustomPaint(
                        size: const Size(double.infinity, 10),
                        painter: _TicksPainter(context.palette.divider))),
                SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                        trackHeight: 1.2,
                        thumbShape: const _InstrumentThumb(),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 18)),
                    child: Slider(
                        semanticFormatterCallback: active.display,
                        value: value,
                        min: active.min,
                        max: active.max,
                        activeColor: context.palette.text,
                        inactiveColor: context.palette.divider,
                        onChangeStart: (_) => widget.onStart(),
                        onChanged: (v) =>
                            widget.onChanged(widget.edits.withValue(active, v)),
                        onChangeEnd: (_) => widget.onEnd())),
              ])),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(active.display(active.min),
                        style: TextStyle(
                            fontSize: 10, color: context.palette.muted)),
                    if (active.min < 0)
                      Text('0',
                          style: TextStyle(
                              fontSize: 10, color: context.palette.muted)),
                    Text(active.display(active.max),
                        style: TextStyle(
                            fontSize: 10, color: context.palette.muted)),
                  ])),
          const SizedBox(height: 14),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final a in widget.adjustments)
                  TextButton(
                      style: TextButton.styleFrom(
                          minimumSize: const Size(48, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          foregroundColor: a == active
                              ? context.palette.text
                              : context.palette.muted,
                          backgroundColor: a == active
                              ? context.palette.divider.withOpacity(.45)
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(3))),
                      onPressed: () {
                        setState(() => _active = a);
                        widget.onActiveChanged?.call(a);
                      },
                      child:
                          Text(a.label, style: const TextStyle(fontSize: 12))),
              ]),
        ]));
  }
}

class _TicksPainter extends CustomPainter {
  _TicksPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 0; i <= 20; i++) {
      final x = size.width * i / 20;
      canvas.drawLine(
          Offset(x, 0),
          Offset(
              x,
              i == 10
                  ? 10
                  : i % 5 == 0
                      ? 7
                      : 4),
          paint);
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) => color != old.color;
}

class _InstrumentThumb extends SliderComponentShape {
  const _InstrumentThumb();
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(4, 24);
  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    context.canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: 3, height: 23),
            const Radius.circular(1)),
        Paint()..color = sliderTheme.thumbColor ?? Colors.white);
  }
}
