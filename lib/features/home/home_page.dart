import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_type.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../../diagnostics/diagnostic_store.dart';
import 'widgets/connection_card.dart';
import 'widgets/home_brand.dart';
import 'widgets/home_cover.dart';
import 'widgets/manual_wifi_dialog.dart';
import 'import_history.dart';
import '../../location/location_recording.dart';
import '../../location/location_controls.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionControllerProvider);
    final controller = ref.read(connectionControllerProvider.notifier);
    return ColoredBox(
        color: context.palette.background,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 23),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 20),
                child: Row(children: [
                  const Expanded(
                      child: Align(
                          alignment: Alignment.centerLeft, child: HomeBrand())),
                  PopupMenuButton<String>(
                    tooltip: '更多连接选项',
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (value) {
                      if (value == 'wifi') {
                        _showManualWifi(context, controller);
                      } else {
                        _showDiagnostics(
                            context, state, ref.read(diagnosticStoreProvider));
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'wifi', child: Text('手动连接 Wi-Fi')),
                      PopupMenuItem(value: 'diagnostics', child: Text('诊断信息')),
                    ],
                  ),
                ]),
              ),
              const HomeCover(),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 23),
                child: ConnectionCard(
                  state: state,
                  onConnect: controller.connect,
                  onRetry: () => _repair(context, controller, state),
                  onSelectDevice: controller.selectDevice,
                  onEnterShoot: () => context.go('/shoot'),
                  onOpenDiagnostics: () => _showDiagnostics(
                    context,
                    state,
                    ref.read(diagnosticStoreProvider),
                  ),
                  onManualWifi: () => _showManualWifi(context, controller),
                  onCancel: controller.cancel,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(23, 0, 23, 0),
                child: _QuickStatus(),
              ),
            ],
          ),
        ));
  }

  Future<void> _repair(
    BuildContext context,
    ConnectionController controller,
    CameraConnectionState state,
  ) async {
    if (state
        case ConnectionFailed(
          failure: ConnectionFailure(
            userAction: ConnectionUserAction.openSettings,
          ),
        )) {
      await openAppSettings();
      return;
    }
    await controller.retry();
  }

  Future<void> _showManualWifi(
    BuildContext context,
    ConnectionController controller,
  ) async {
    final credentials = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const ManualWifiDialog(),
    );
    if (credentials == null) return;
    await controller.connectWifiManually(
      ssid: credentials.$1,
      passphrase: credentials.$2,
    );
  }

  void _showDiagnostics(
    BuildContext context,
    CameraConnectionState state,
    DiagnosticStore store,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('诊断信息', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('当前阶段：${state.stage.name} · ${store.length} 条事件'),
              const SizedBox(height: 8),
              const Text('敏感标识、密码与图像数据不会显示或导出。'),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () async {
                  final export = store.exportJson();
                  await store.persist();
                  await Clipboard.setData(ClipboardData(text: export));
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('复制脱敏 JSON'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  context.push('/probe');
                },
                icon: const Icon(Icons.manage_search_outlined),
                label: const Text('协议探测'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickStatus extends ConsumerWidget {
  const _QuickStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationRecordingProvider);
    return Column(children: [
      const ImportStatusTile(),
      const SizedBox(height: 0),
      _StatusCell(
          icon: Icons.location_on_outlined,
          label: '位置记录',
          value: location.error != null
              ? '需检查'
              : location.active
                  ? '记录中'
                  : location.enabled
                      ? '待拍摄'
                      : '关闭',
          onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: context.palette.surface,
              builder: (_) => const LocationControls())),
    ]);
  }
}

class _StatusCell extends StatelessWidget {
  const _StatusCell(
      {required this.icon,
      required this.label,
      required this.value,
      this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 19),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.palette.divider)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: context.palette.muted),
              const SizedBox(width: 12),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: context.palette.text)),
              const Spacer(),
              Text(value,
                  style: GRemoteType.numeric
                      .copyWith(color: context.palette.muted)),
            ],
          ),
        ));
  }
}
