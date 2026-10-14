import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

class ShutterButton extends StatefulWidget {
  const ShutterButton({
    required this.enabled,
    required this.onPressed,
    required this.onReleased,
    super.key,
  });

  final bool enabled;
  final Future<void> Function() onPressed;
  final Future<void> Function() onReleased;

  @override
  State<ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<ShutterButton> {
  var _pressed = false;
  Future<void>? _pressOperation;
  var _gestureEpoch = 0;

  @override
  void didUpdateWidget(covariant ShutterButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _gestureEpoch++;
      _pressed = false;
      _pressOperation = null;
    }
  }

  void _press() {
    if (!widget.enabled || _pressed) return;
    setState(() => _pressed = true);
    final operation = Future<void>.sync(widget.onPressed);
    _pressOperation = operation;
    unawaited(operation.catchError((Object _) {}));
  }

  void _release() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    final pressOperation = _pressOperation;
    _pressOperation = null;
    unawaited(_releaseAfter(pressOperation, _gestureEpoch));
  }

  Future<void> _releaseAfter(Future<void>? pressOperation, int epoch) async {
    try {
      await pressOperation;
      if (!mounted || epoch != _gestureEpoch || !widget.enabled) return;
      await widget.onReleased();
    } catch (_) {
      // 上层状态负责展示平台错误；此处只保证手势 Future 不会泄漏。
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: '快门',
      child: GestureDetector(
        key: const Key('shutter-button'),
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => _press() : null,
        onTapUp: widget.enabled ? (_) => _release() : null,
        onTapCancel: widget.enabled ? _release : null,
        child: AnimatedScale(
          scale: _pressed ? 0.91 : 1,
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 160),
            width: 86,
            height: 86,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: GRemoteColors.night,
              border: Border.all(
                color: widget.enabled
                    ? GRemoteColors.goldSoft
                    : GRemoteColors.muted,
                width: 2.5,
              ),
              boxShadow: widget.enabled
                  ? const [
                      BoxShadow(
                        color: Color(0x44C4A36D),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.enabled
                    ? (_pressed ? GRemoteColors.gold : GRemoteColors.text)
                    : GRemoteColors.raised,
                border: Border.all(color: GRemoteColors.divider),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
