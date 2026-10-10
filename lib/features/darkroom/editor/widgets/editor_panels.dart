import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../darkroom/model/edit_document.dart';
import '../../../../darkroom/model/export_recipe.dart';
import '../editor_controller.dart';

const _hint = TextStyle(color: GRemoteColors.muted, fontSize: 12);

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
