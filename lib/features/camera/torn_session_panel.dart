import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_presence.dart';
import '../film_workbench/companion_providers.dart';
import 'extensions_providers.dart';

/// Native session controls only. Live view always remains the camera's image.
class TornSessionPanel extends ConsumerStatefulWidget {
  const TornSessionPanel(
      {super.key, this.shooting = false, this.active = true});
  final bool shooting;
  final bool active;
  @override
  ConsumerState<TornSessionPanel> createState() => _TornSessionPanelState();
}

class _TornSessionPanelState extends ConsumerState<TornSessionPanel> {
  Timer? _timer;
  bool _polling = false;
  bool _visible = false;

  void _schedule(bool enabled) {
    if (!enabled) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    }
  }

  Future<void> _refresh() async {
    if (!mounted ||
        !_visible ||
        !widget.active ||
        _polling ||
        !ref.read(appForegroundProvider) ||
        !ref.read(companionNetworkReadyProvider) ||
        (widget.shooting && !ref.read(shootPageVisibleProvider))) return;
    final controller = ref.read(cameraExtensionsControllerProvider);
    if (controller == null || controller.working) return;
    _polling = true;
    try {
      await controller.refresh();
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(cameraExtensionsControllerProvider);
    final connected = ref.watch(companionNetworkReadyProvider);
    final foreground = ref.watch(appForegroundProvider);
    final visible = widget.active &&
        TickerMode.of(context) &&
        (!widget.shooting || ref.watch(shootPageVisibleProvider));
    _visible = visible;
    _schedule(controller != null && connected && foreground && visible);
    if (controller == null) {
      return widget.shooting
          ? const SizedBox.shrink()
          : const SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('撕纸效果', style: TextStyle(fontSize: 14)),
              subtitle: Text('连接相机后可用', style: TextStyle(fontSize: 11)),
              value: false,
              onChanged: null);
    }
    return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final stage = controller.snapshot?.values['tornSession'];
          final supported = controller.capabilities?.supported
                      .contains('tornSession') ==
                  true &&
              controller.snapshot?.supported.contains('tornSession') == true;
          if (widget.shooting) {
            final progress = connected && supported
                ? switch (stage) {
                    1 => '撕纸效果已开启',
                    2 => '撕纸效果待拍素材',
                    4 => '撕纸效果未完成',
                    _ => null,
                  }
                : null;
            return progress == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(progress,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall),
                  );
          }
          final armed = stage == 1 || stage == 2;
          final editable = visible &&
              connected &&
              foreground &&
              controller.canWrite &&
              supported;
          final restriction = supported && !armed
              ? controller.snapshot?.values['aspect'] == 6
                  ? '请先关闭 Half'
                  : controller.tornStartRestriction?.call()
              : null;
          final status = switch (stage) {
            1 => '已开启',
            2 => '待拍素材',
            3 => '合成处理完成',
            4 => '本次未合成',
            _ => '关闭',
          };
          final subtitle = controller.pending
              ? '结果待核对'
              : !connected
                  ? '连接相机后可用'
                  : controller.unsupported ||
                          (controller.snapshot != null && !supported)
                      ? '此机身暂不支持'
                      : controller.snapshot == null
                          ? '尚未读取机身状态'
                          : restriction ?? status;
          final revision = controller.snapshot?.revision;
          return SwitchListTile(
            key: const ValueKey('extension-torn-session'),
            contentPadding: EdgeInsets.zero,
            title: const Text('撕纸效果', style: TextStyle(fontSize: 14)),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
            value: armed,
            onChanged: editable && restriction == null && revision != null
                ? (on) => controller.set('tornSession', on ? 1 : 0,
                    expectedRevision: revision)
                : null,
          );
        });
  }
}
