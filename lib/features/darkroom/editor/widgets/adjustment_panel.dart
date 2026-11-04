import 'package:flutter/material.dart';
import 'precision_dialog.dart';
import 'editor_ruler.dart';

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
      this.activeAdjustment,
      this.onOpenParameters,
      super.key});
  final PhotoEdits edits;
  final List<PhotoAdjustment> adjustments;
  final ValueChanged<PhotoEdits> onChanged;
  final VoidCallback onStart, onEnd;
  final ValueChanged<PhotoAdjustment>? onActiveChanged;
  final PhotoAdjustment? activeAdjustment;
  final VoidCallback? onOpenParameters;
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

  Future<void> _select() async {
    final next = await showModalBottomSheet<PhotoAdjustment>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              for (final a in widget.adjustments)
                ListTile(
                    title: Text(a.label),
                    onTap: () => Navigator.pop(context, a)),
            ])));
    if (!mounted || next == null) return;
    setState(() => _active = next);
    widget.onActiveChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.adjustments.isEmpty) return const SizedBox.shrink();
    final selection = widget.activeAdjustment ?? _active;
    final active = widget.adjustments.contains(selection)
        ? selection!
        : widget.adjustments.first;
    final value = widget.edits.value(active);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 44,
          child: Stack(alignment: Alignment.center, children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: widget.adjustments.length == 1
                  ? Text(active.label, style: const TextStyle(fontSize: 13))
                  : TextButton(
                      key: const ValueKey('adjustment-parameters'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.only(right: 8),
                        foregroundColor: context.palette.text,
                      ),
                      onPressed: widget.onOpenParameters ?? _select,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(active.label,
                            style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        const EditorChevron(),
                      ]),
                    ),
            ),
            GestureDetector(
              key: const ValueKey('adjustment-value'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _precise(active),
              onDoubleTap: () => _reset(active),
              child: Semantics(
                button: true,
                label: '${active.label}，${active.display(value)}，精确调节',
                excludeSemantics: true,
                child: SizedBox(
                  width: 62,
                  height: 44,
                  child: Center(
                      child: Text(active.display(value),
                          style: const TextStyle(
                              fontSize: 13,
                              fontFeatures: [FontFeature.tabularFigures()]))),
                ),
              ),
            ),
          ]),
        ),
        EditorRuler(
          value: value,
          min: active.min,
          max: active.max,
          format: active.display,
          onStart: widget.onStart,
          onEnd: widget.onEnd,
          onChanged: (v) => widget.onChanged(widget.edits.withValue(active, v)),
        ),
      ]),
    );
  }
}
