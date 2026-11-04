import 'package:flutter/material.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../darkroom/model/photo_edits.dart';

enum EditorTool {
  basic('调整图片', Icons.tune, [
    PhotoAdjustment.exposure,
    PhotoAdjustment.contrast,
    PhotoAdjustment.highlights,
    PhotoAdjustment.shadows,
    PhotoAdjustment.whites,
    PhotoAdjustment.blacks
  ]),
  crop('裁切', Icons.crop, []),
  balance('调色', Icons.palette_outlined, [
    PhotoAdjustment.temperature,
    PhotoAdjustment.tint,
    PhotoAdjustment.saturation,
    PhotoAdjustment.vibrance
  ]),
  curves('曲线', Icons.show_chart, []),
  lut('LUT', Icons.movie_filter_outlined, []),
  grain('颗粒', Icons.grain, [
    PhotoAdjustment.grain,
    PhotoAdjustment.grainSize,
    PhotoAdjustment.grainRoughness
  ]),
  vignette('暗角', Icons.vignette_outlined, [
    PhotoAdjustment.vignette,
    PhotoAdjustment.vignetteSize,
    PhotoAdjustment.vignetteFeather
  ]),
  leak('漏光', Icons.wb_twilight, [
    PhotoAdjustment.leak,
    PhotoAdjustment.leakPosition,
    PhotoAdjustment.leakSpread,
    PhotoAdjustment.leakHue
  ]),
  halation('光晕', Icons.wb_sunny_outlined, [
    PhotoAdjustment.halation,
    PhotoAdjustment.halationRadius,
    PhotoAdjustment.halationThreshold
  ]),
  bloom('柔光', Icons.blur_on, [
    PhotoAdjustment.bloom,
    PhotoAdjustment.bloomRadius,
    PhotoAdjustment.bloomThreshold
  ]),
  fade('褪色', Icons.tonality, [PhotoAdjustment.fade]),
  monochrome('黑白', Icons.contrast, [PhotoAdjustment.monochrome]),
  frame('边框', Icons.crop_square, []),
  stamp('日期印记', Icons.date_range_outlined, []),
  processVersion('新版调色', Icons.auto_awesome_outlined, []),
  presets('预设', Icons.bookmark_border, []),
  history('编辑记录', Icons.history, []);

  const EditorTool(this.label, this.icon, this.adjustments);
  final String label;
  final IconData icon;
  final List<PhotoAdjustment> adjustments;
}

class EditorTools extends StatelessWidget {
  const EditorTools(
      {required this.onSelected, required this.changed, super.key});
  final ValueChanged<EditorTool> onSelected;
  final bool Function(EditorTool) changed;
  static const _tools = [
    EditorTool.basic,
    EditorTool.curves,
    EditorTool.crop,
    EditorTool.balance,
    EditorTool.grain,
    EditorTool.vignette,
    EditorTool.lut,
    EditorTool.leak,
    EditorTool.halation,
    EditorTool.bloom,
    EditorTool.fade,
    EditorTool.monochrome,
    EditorTool.frame,
    EditorTool.stamp,
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      key: const ValueKey('editor-tool-ribbon'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Row(children: [
        for (final tool in _tools)
          Semantics(
            button: true,
            label: '打开${tool.label}',
            child: InkWell(
              onTap: () => onSelected(tool),
              child: SizedBox(
                width: 68,
                height: 76,
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(clipBehavior: Clip.none, children: [
                        if (tool == EditorTool.curves)
                          CustomPaint(
                              size: const Size.square(21),
                              painter: _CurveToolIcon(context.palette.text))
                        else
                          Icon(tool.icon, size: 21),
                        if (changed(tool))
                          const Positioned(
                              right: -7,
                              top: 0,
                              child: SizedBox(
                                width: 4,
                                height: 4,
                                child: ColoredBox(color: Color(0xff3c83b8)),
                              )),
                      ]),
                      const SizedBox(height: 7),
                      Text(tool.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: context.palette.text)),
                    ]),
              ),
            ),
          ),
      ]));
}

class _CurveToolIcon extends CustomPainter {
  const _CurveToolIcon(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(Offset(2.5 + i * 4, 18.5), .6, ink);
      if (i > 0) canvas.drawCircle(Offset(2.5, 18.5 - i * 4), .6, ink);
    }
    canvas.drawPath(
      Path()
        ..moveTo(4.5, 15)
        ..cubicTo(12, 15, 16, 12, 17.5, 3.5),
      stroke,
    );
    canvas.drawCircle(const Offset(4.5, 15), 1.5, ink);
    canvas.drawCircle(const Offset(17.5, 3.5), 1.5, ink);
  }

  @override
  bool shouldRepaint(_CurveToolIcon oldDelegate) => oldDelegate.color != color;
}
