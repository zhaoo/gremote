import 'package:flutter/material.dart';

import '../../../camera/live/live_frame_analyzer.dart';

class HistogramOverlay extends StatelessWidget {
  const HistogramOverlay(this.stats, {super.key});

  final FrameStats? stats;

  @override
  Widget build(BuildContext context) => Positioned(
        left: 10,
        bottom: 10,
        child: SizedBox(
          width: 110,
          height: 48,
          child: CustomPaint(painter: _HistogramPainter(stats?.histogram)),
        ),
      );
}

class _HistogramPainter extends CustomPainter {
  _HistogramPainter(this.bins);
  final List<int>? bins;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0x88000000));
    final values = bins;
    if (values == null || values.isEmpty) return;
    final max = values.reduce((a, b) => a > b ? a : b);
    if (max == 0) return;
    final path = Path()..moveTo(0, size.height);
    for (var i = 0; i < values.length; i++) {
      path.lineTo(i * size.width / (values.length - 1),
          size.height * (1 - values[i] / max));
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xAAFFFFFF));
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) =>
      oldDelegate.bins != bins;
}
