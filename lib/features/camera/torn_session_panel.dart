import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_presence.dart';
import '../../camera/companion/extensions_protocol.dart';
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
          : const ListTile(
              title: Text('撕纸叠映'), subtitle: Text('连接支持此功能的机身后使用'));
    }
    return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final stage = controller.snapshot?.values['tornSession'];
          final supported = controller.capabilities?.supported
                      .contains('tornSession') ==
                  true &&
              controller.snapshot?.supported.contains('tornSession') == true;
          if (widget.shooting && (!supported || stage == null || stage == 0)) {
            return const SizedBox.shrink();
          }
          final editable = visible &&
              connected &&
              foreground &&
              controller.canWrite &&
              supported;
          final restriction =
              supported ? controller.tornStartRestriction?.call() : null;
          final half = controller.snapshot?.values['aspect'] == 6;
          final status = !supported
              ? '此机身暂不支持'
              : extensionFields['tornSession']!.display(stage ?? 0);
          final hint = switch (stage) {
            1 => '先拍白底暗色撕纸轮廓，再拍素材；请手动按快门。',
            2 => '轮廓已准备，请手动拍摄素材。',
            3 => '合成处理完成，请在相机中核对成片与保存状态。',
            4 => '本次未合成，请在扩展中重新开始。',
            _ => '两次拍摄由机身处理；取景画面不预览合成效果。',
          };
          return Padding(
            key: const ValueKey('torn-session-panel'),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('撕纸叠映', style: Theme.of(context).textTheme.titleSmall),
              Text(status),
              if (!connected) const Text('连接已断开 · 阶段待重新读取'),
              if (supported)
                Text(hint, style: Theme.of(context).textTheme.bodySmall),
              if (controller.pending) const Text('结果待核对，请勿重复提交'),
              if (widget.shooting) ...[
                const Text('取消或重新开始：返回「相机 → 扩展 → 功能」。',
                    style: TextStyle(fontSize: 11)),
                TextButton(
                    onPressed: connected && foreground && !controller.working
                        ? _refresh
                        : null,
                    child: const Text('重新读取叠映阶段')),
              ] else ...[
                if (supported && (half || restriction != null))
                  Text(half ? '请先关闭 Half 再开始撕纸叠映' : restriction!),
                Wrap(spacing: 8, children: [
                  TextButton(
                      onPressed: editable && !half && restriction == null
                          ? () => controller.set('tornSession', 1,
                              expectedRevision: controller.snapshot!.revision)
                          : null,
                      child: Text(stage == null || stage == 0 ? '开始' : '重新开始')),
                  TextButton(
                      onPressed: editable && stage != null && stage != 0
                          ? () => controller.set('tornSession', 0,
                              expectedRevision: controller.snapshot!.revision)
                          : null,
                      child: const Text('取消叠映')),
                ]),
              ],
            ]),
          );
        });
  }
}
