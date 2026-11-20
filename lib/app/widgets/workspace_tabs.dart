import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'workspace_motion.dart';

class WorkspaceTabs<T> extends StatelessWidget {
  const WorkspaceTabs(
      {required this.items,
      required this.value,
      required this.onChanged,
      this.disabledItems = const {},
      super.key});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final Set<T> disabledItems;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (item, label) in items)
            Semantics(
              selected: item == value,
              enabled: !disabledItems.contains(item),
              child: TextButton(
                onPressed: disabledItems.contains(item)
                    ? null
                    : () {
                        if (item != value) onChanged(item);
                      },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(48, 44),
                  foregroundColor: item == value
                      ? context.palette.text
                      : context.palette.muted,
                ),
                child: AnimatedDefaultTextStyle(
                  duration: WorkspaceMotion.duration(context, 160),
                  style: (Theme.of(context).textTheme.bodyMedium ??
                          const TextStyle())
                      .copyWith(
                          fontSize: 15,
                          color: disabledItems.contains(item)
                              ? context.palette.muted.withValues(alpha: .45)
                              : item == value
                                  ? context.palette.text
                                  : context.palette.muted,
                          fontWeight: item == value
                              ? FontWeight.w500
                              : FontWeight.w400),
                  child: Text(label),
                ),
              ),
            ),
        ],
      );
}
