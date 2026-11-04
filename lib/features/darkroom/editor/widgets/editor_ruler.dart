import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';

const editorMarker = Color(0xffedbd26);

class EditorRuler extends StatelessWidget {
  const EditorRuler({
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
    super.key,
  });

  final double value, min, max;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final VoidCallback onStart, onEnd;

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 34,
      child: Stack(fit: StackFit.expand, children: [
        IgnorePointer(
            child: CustomPaint(painter: _RulerTicks(context.palette.text))),
        SliderTheme(
            data: SliderTheme.of(context).copyWith(
                trackShape: const _RulerTrack(),
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const _RulerMarker(),
                thumbColor: editorMarker),
            child: Slider(
                value: value,
                min: min,
                max: max,
                semanticFormatterCallback: format,
                onChangeStart: (_) => onStart(),
                onChanged: onChanged,
                onChangeEnd: (_) => onEnd()))
      ]));
}

class _RulerTicks extends CustomPainter {
  const _RulerTicks(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final span = size.width - 8;
    for (var i = 0; i <= 50; i++) {
      final x = 4 + span * i / 50;
      final length = i % 5 == 0 ? 11.0 : 8.0;
      canvas.drawLine(
          Offset(x, 23 - length / 2), Offset(x, 23 + length / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_RulerTicks oldDelegate) => oldDelegate.color != color;
}

class _RulerTrack extends RoundedRectSliderTrackShape {
  const _RulerTrack();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) =>
      Rect.fromLTWH(offset.dx + 4, offset.dy + parentBox.size.height / 2,
          parentBox.size.width - 8, 0);

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
    double additionalActiveTrackHeight = 0,
  }) {}
}

class _RulerMarker extends SliderComponentShape {
  const _RulerMarker();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(8, 26);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final x = center.dx, y = center.dy;
    final paint = Paint()..color = editorMarker;
    context.canvas.drawPath(
        Path()
          ..moveTo(x - 4, y - 13)
          ..lineTo(x + 4, y - 13)
          ..lineTo(x, y - 7)
          ..close(),
        paint);
    context.canvas.drawRect(Rect.fromLTWH(x - 1, y - 4, 2, 16), paint);
  }
}

/// A quiet disclosure mark shared by the parameter label and the editor dock.
class EditorChevron extends StatelessWidget {
  const EditorChevron({this.up = false, super.key});
  final bool up;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(12, 12),
        painter: _EditorChevronPainter(context.palette.text, up),
      );
}

class _EditorChevronPainter extends CustomPainter {
  const _EditorChevronPainter(this.color, this.up);
  final Color color;
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    final delta = up ? -1.5 : 1.5;
    canvas.drawPath(
      Path()
        ..moveTo(2.5, middle - delta)
        ..lineTo(size.width / 2, middle + delta)
        ..lineTo(size.width - 2.5, middle - delta),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_EditorChevronPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.up != up;
}
