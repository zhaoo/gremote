import 'package:flutter/material.dart';

abstract final class WorkspaceMotion {
  static Duration duration(BuildContext context, int milliseconds) {
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ||
            media?.accessibleNavigation == true
        ? Duration.zero
        : Duration(milliseconds: milliseconds);
  }
}

/// Removed content loses hit targets immediately; only its surrounding size moves.
class WorkspaceReveal extends StatelessWidget {
  const WorkspaceReveal(
      {required this.visible, required this.child, super.key});
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = visible ? child : const SizedBox(width: double.infinity);
    final duration = WorkspaceMotion.duration(context, 200);
    if (duration == Duration.zero) return content;
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: content,
    );
  }
}
