import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'workspace_motion.dart';

class WorkspaceTabs<T> extends StatelessWidget {
  const WorkspaceTabs(
      {required this.items,
      required this.value,
      required this.onChanged,
      super.key});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (item, label) in items)
            Semantics(
              selected: item == value,
              child: TextButton(
                onPressed: () {
                  if (item != value) onChanged(item);
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(48, 44),
                  foregroundColor:
                      item == value ? GRemoteColors.text : GRemoteColors.muted,
                ),
                child: AnimatedDefaultTextStyle(
                  duration: WorkspaceMotion.duration(context, 160),
                  style: TextStyle(
                      fontSize: 15,
                      color: item == value
                          ? GRemoteColors.text
                          : GRemoteColors.muted,
                      fontWeight:
                          item == value ? FontWeight.w500 : FontWeight.w400),
                  child: Text(label),
                ),
              ),
            ),
        ],
      );
}
