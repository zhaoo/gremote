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
import 'widgets/manual_wifi_dialog.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionControllerProvider);
    final controller = ref.read(connectionControllerProvider.notifier);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(top: 16, bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('GRemote',
                          style: TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 34,
                              height: 1,
                              color: GRemoteColors.text)),
                      const SizedBox(height: 4),
                      Text('STREET CAMERA COMPANION',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  color: GRemoteColors.gold,
                                  fontSize: 9,
                                  letterSpacing: 2.1)),
                    ])),
                if (MediaQuery.sizeOf(context).width >= 380) ...[
                  const SizedBox(width: 8),
                  const Text('记 录 日 常\n成 为 特 别',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 9,
                          height: 1.7,
                          letterSpacing: 1,
                          color: GRemoteColors.muted)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _EditorialHero(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
            padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _QuickStatus(),
          ),
        ],
      ),
    );
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

class _EditorialHero extends StatelessWidget {
  const _EditorialHero();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 238,
        child: Stack(fit: StackFit.expand, children: [
          Image.asset('assets/images/street_moment.jpg', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0x77111411), Color(0x00111411)],
              ),
            ),
          ),
          Positioned(
            top: 17,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('走上街头', style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: 6),
                const Text('让平凡的日子，留下不平凡的眼光。',
                    style: TextStyle(
                        color: GRemoteColors.text,
                        fontSize: 11,
                        letterSpacing: 0.6,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
              ],
            ),
          ),
          const Positioned(
            left: 20,
            bottom: 20,
            child: Text('A QUIETER\nBRIGHTER\nYOU  ─',
                style: TextStyle(
                    color: GRemoteColors.text,
                    fontSize: 8,
                    height: 1.5,
                    letterSpacing: 1.6)),
          ),
          if (MediaQuery.sizeOf(context).width >= 360)
            const Positioned(
              right: 21,
              top: 82,
              child: Text('GOOD\nPHOTOS\nBETTER\nDAYS  ─',
                  style: TextStyle(
                      color: GRemoteColors.night,
                      fontSize: 9,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
            ),
        ]),
      );
}

class _QuickStatus extends StatelessWidget {
  const _QuickStatus();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _StatusCell(
            icon: Icons.file_download_outlined, label: '今日导入', value: '—'),
        SizedBox(height: 6),
        _StatusCell(
            icon: Icons.location_on_outlined, label: '位置记录', value: '关闭'),
      ],
    );
  }
}

class _StatusCell extends StatelessWidget {
  const _StatusCell(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: GRemoteColors.navy,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: GRemoteColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: GRemoteColors.goldSoft),
          const SizedBox(width: 12),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: GRemoteColors.text)),
          const Spacer(),
          Text(value,
              style:
                  GRemoteType.numeric.copyWith(color: GRemoteColors.goldSoft)),
        ],
      ),
    );
  }
}
