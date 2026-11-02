import 'package:flutter/material.dart';

import '../../../../app/widgets/workspace_motion.dart';
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
              onDoubleTap: () => _reset(active),
              child: Semantics(
                  label: '${active.label}，${active.display(value)}，双击恢复默认值',
                  excludeSemantics: true,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(children: [
                        Expanded(
                            child: RichText(
                                textScaler: MediaQuery.textScalerOf(context),
                                text: TextSpan(
                                    text: active.label,
                                    style: DefaultTextStyle.of(context)
                                        .style
                                        .copyWith(
                                            fontSize: 13,
                                            color: const Color(0xffdddeda))))),
                        const SizedBox(width: 12),
                        Text(active.display(value),
                            style: const TextStyle(
                                fontFamily: 'GRemoteEditorial',
                                fontFamilyFallback: ['Georgia', 'serif'],
                                fontSize: 26,
                                color: Color(0xfff0f0e9))),
                      ])))),
          Slider(
              semanticFormatterCallback: active.display,
              value: value,
              min: active.min,
              max: active.max,
              activeColor: Colors.white,
              inactiveColor: Colors.white24,
              onChangeStart: (_) => widget.onStart(),
              onChanged: (v) =>
                  widget.onChanged(widget.edits.withValue(active, v)),
              onChangeEnd: (_) => widget.onEnd()),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(active.display(active.min),
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white38)),
                    if (active.min < 0)
                      const Text('0',
                          style:
                              TextStyle(fontSize: 10, color: Colors.white38)),
                    Text(active.display(active.max),
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white38)),
                  ])),
          const SizedBox(height: 14),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final a in widget.adjustments)
                  ChoiceChip(
                      label: Text(a.label),
                      selected: a == active,
                      onSelected: (_) {
                        setState(() => _active = a);
                        widget.onActiveChanged?.call(a);
                      },
                      showCheckmark: false,
                      selectedColor: const Color(0xff343a3c),
                      backgroundColor: const Color(0xff202628),
                      labelStyle: TextStyle(
                          fontSize: 12,
                          color: a == active
                              ? const Color(0xfff0f0e9)
                              : Colors.white54),
                      visualDensity: VisualDensity.standard,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                      chipAnimationStyle: ChipAnimationStyle(
                          selectAnimation: AnimationStyle(
                              duration:
                                  WorkspaceMotion.duration(context, 130)))),
              ]),
        ]));
  }
}
