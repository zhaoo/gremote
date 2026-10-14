import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../darkroom/frame/frame_layout.dart';
import '../../../../darkroom/frame/frame_painter.dart';
import '../../../../darkroom/model/edit_document.dart';
import '../../../../darkroom/model/export_recipe.dart';
import '../editor_controller.dart';

const _hint = TextStyle(color: GRemoteColors.muted, fontSize: 12);

class FrameStylePanel extends StatelessWidget {
  const FrameStylePanel(
      {required this.state, required this.controller, super.key});

  final EditorState state;
  final EditorController controller;

  static String _description(FrameStyle style) => switch (style) {
        FrameStyle.none => '不添加边框和文字',
        FrameStyle.classic => '干净留白，轻量注释',
        FrameStyle.street => '深色衬底，低调暖金',
        FrameStyle.contact => '细窄片孔，胶片印样',
      };

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final style in [
              FrameStyle.none,
              FrameStyle.classic,
              FrameStyle.street,
              FrameStyle.contact
            ])
              LayoutBuilder(builder: (context, constraints) {
                final selected = state.recipe.frame == style;
                return Semantics(
                  button: true,
                  selected: selected,
                  child: SizedBox(
                    width: (constraints.maxWidth - 10) / 2,
                    child: Material(
                      color:
                          selected ? GRemoteColors.raised : GRemoteColors.navy,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => controller.setFrame(style),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: selected
                                    ? GRemoteColors.gold
                                    : GRemoteColors.divider),
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  SizedBox(
                                      width: 44,
                                      height: 28,
                                      child: CustomPaint(
                                          painter: _FrameSwatch(style))),
                                  const Spacer(),
                                  if (selected)
                                    const Icon(Icons.check_circle_rounded,
                                        color: GRemoteColors.gold, size: 17),
                                ]),
                                const SizedBox(height: 7),
                                Text(style.label,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(_description(style),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: GRemoteColors.muted,
                                        fontSize: 10)),
                              ]),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ]),
        ],
      );
}

class _FrameSwatch extends CustomPainter {
  const _FrameSwatch(this.style);
  final FrameStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = computeFrameLayout(
        photoWidth: 240,
        photoHeight: 160,
        style: style,
        ratio: FrameRatio.original,
        content: const FrameContent(model: 'RICOH GR III'));
    final scale = math.min(
        size.width / layout.canvasWidth, size.height / layout.canvasHeight);
    canvas.save();
    canvas.translate((size.width - layout.canvasWidth * scale) / 2,
        (size.height - layout.canvasHeight * scale) / 2);
    canvas.scale(scale);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, layout.canvasWidth.toDouble(),
            layout.canvasHeight.toDouble()),
        Paint()..color = Color(layout.background));
    final photo = layout.photo;
    canvas.drawRect(
        Rect.fromLTWH(photo.x.toDouble(), photo.y.toDouble(),
            photo.width.toDouble(), photo.height.toDouble()),
        Paint()
          ..shader = const LinearGradient(
                  colors: [Color(0xFFADB4AC), Color(0xFF454C48)])
              .createShader(const Rect.fromLTWH(0, 0, 240, 160)));
    for (final overlay in layout.overlays) {
      canvas.save();
      canvas.translate(overlay.rect.x.toDouble(), overlay.rect.y.toDouble());
      FramePainter.paintOverlay(canvas, overlay);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FrameSwatch oldDelegate) => oldDelegate.style != style;
}

class LutPanel extends StatelessWidget {
  const LutPanel({required this.state, required this.controller, super.key});

  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final recipe = state.recipe;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _choice(
                  '原色', recipe.lutId == null, () => controller.setLut(null)),
              for (final lut in state.luts)
                _choice(lut.imported ? '${lut.name} · 导入' : lut.name,
                    recipe.lutId == lut.id, () => controller.setLut(lut.id)),
            ],
          ),
        ),
        if (recipe.lutId != null) ...[
          const SizedBox(height: 12),
          Text('强度 ${(recipe.strength * 100).round()}%', style: _hint),
          Slider(
            value: recipe.strength,
            onChanged: controller.setStrength,
            onChangeEnd: (_) => controller.regrade(),
          ),
        ],
      ],
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
            label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

class ChoicePanel<T> extends StatelessWidget {
  const ChoicePanel({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.note,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  final String? note;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final value in values)
              ChoiceChip(
                label: Text(label(value)),
                selected: value == selected,
                onSelected: (_) => onSelected(value),
              ),
          ]),
          if (note != null) ...[
            const SizedBox(height: 12),
            Text(note!, style: _hint),
          ],
        ],
      );
}

class InfoPanel extends StatefulWidget {
  const InfoPanel({required this.state, required this.controller, super.key});

  final EditorState state;
  final EditorController controller;

  @override
  State<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<InfoPanel> {
  late final _title = TextEditingController(text: widget.state.doc?.title);
  late final _location =
      TextEditingController(text: widget.state.doc?.location);

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hidden = widget.state.doc?.hidden ?? const {};
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '标题'),
              onChanged: widget.controller.setTitle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _location,
              decoration: const InputDecoration(labelText: '地点'),
              onChanged: widget.controller.setLocation,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final field in FrameField.values)
            FilterChip(
              label: Text(field.label),
              selected: !hidden.contains(field),
              onSelected: (_) => widget.controller.toggleField(field),
            ),
        ]),
      ],
    );
  }
}

class ExportPanel extends StatelessWidget {
  const ExportPanel({required this.state, required this.controller, super.key});

  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final recipe = state.recipe;
    final hasGps = state.meta?.hasGps ?? false;
    final canKeepGps = state.locationAccess && hasGps;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final size in ExportSize.values)
            ChoiceChip(
              label: Text(size.label),
              selected: recipe.size == size,
              onSelected: (_) => controller.setSize(size),
            ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final quality in exportQualities)
            ChoiceChip(
              label: Text('质量 $quality'),
              selected: recipe.quality == quality,
              onSelected: (_) => controller.setQuality(quality),
            ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('保留 GPS'),
          subtitle: Text(
            !state.locationAccess
                ? '未授予“媒体位置”权限，读取原图时系统已抹去 GPS'
                : hasGps
                    ? '导出副本将包含拍摄位置'
                    : '原图没有 GPS 信息',
            style: _hint,
          ),
          value: canKeepGps && recipe.keepGps,
          onChanged: canKeepGps ? controller.setKeepGps : null,
        ),
        if (!state.locationAccess)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: controller.requestLocationAccess,
              child: const Text('授予媒体位置权限'),
            ),
          ),
      ],
    );
  }
}
