import 'package:flutter/material.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../darkroom/model/photo_edits.dart';

enum EditorTool {
  basic('基础', Icons.tune, [
    PhotoAdjustment.exposure,
    PhotoAdjustment.contrast,
    PhotoAdjustment.highlights,
    PhotoAdjustment.shadows,
    PhotoAdjustment.whites,
    PhotoAdjustment.blacks
  ]),
  crop('裁切', Icons.crop, []),
  balance('白平衡', Icons.thermostat_outlined, [
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
  @override
  Widget build(BuildContext context) => GridView.builder(
      key: const ValueKey('editor-tool-grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisExtent:
              MediaQuery.textScalerOf(context).scale(12) > 18 ? 92 : 74),
      itemCount: EditorTool.values.length,
      itemBuilder: (context, index) {
        final tool = EditorTool.values[index];
        return Semantics(
            button: true,
            label: '打开${tool.label}',
            child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelected(tool),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(clipBehavior: Clip.none, children: [
                        Icon(tool.icon, size: 23),
                        if (changed(tool))
                          Positioned(
                              right: -7,
                              top: 0,
                              child: Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                      color: context.palette.accent,
                                      shape: BoxShape.circle)))
                      ]),
                      const SizedBox(height: 9),
                      Text(tool.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12))
                    ])));
      });
}
