import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../../camera/protocol/protocol_profile.dart';
import '../../camera/sync/camera_state_controller.dart';
import '../../diagnostics/protocol_probe.dart';

class ProtocolProbePage extends ConsumerStatefulWidget {
  const ProtocolProbePage({super.key});

  @override
  ConsumerState<ProtocolProbePage> createState() => _ProtocolProbePageState();
}

class _ProtocolProbePageState extends ConsumerState<ProtocolProbePage> {
  ProbeReport? _report;
  var _running = false;
  String? _error;

  Future<void> _run({required bool includeWrite}) async {
    if (includeWrite && !await _confirmWrite()) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final controller = ref.read(cameraStateControllerProvider.notifier);
      final report = await ProtocolProbe(
        api: controller.api,
        socket: ref.read(cameraGatewaysProvider).changes,
      ).run(includeWrite: includeWrite);
      final connection = ref.read(connectionControllerProvider);
      if (connection case ConnectionReady(:final snapshot)) {
        final current = controller.profile ??
            ProtocolProfile(firmware: snapshot.identity.firmware);
        await controller.saveProfile(current.copyWith(
          writeEncoding: includeWrite ? report.preferredEncoding : null,
          webSocket: report.webSocket,
          probedAt: DateTime.now(),
        ));
      }
      if (mounted) setState(() => _report = report);
    } on Exception {
      if (mounted) setState(() => _error = '探测失败，请确认相机仍已连接');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<bool> _confirmWrite() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('含写入探测'),
          content: const Text('将把当前曝光补偿原值写回相机三次，用于识别写入格式。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('继续'),
            ),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(connectionControllerProvider) is ConnectionReady;
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('协议探测')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('只读探测会读取路由状态、参数结构和变化推送，不记录 SSID、序列号等敏感值。',
                style: TextStyle(color: GRemoteColors.muted, height: 1.5)),
            const SizedBox(height: 18),
            FilledButton(
              onPressed:
                  ready && !_running ? () => _run(includeWrite: false) : null,
              child: const Text('只读探测'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed:
                  ready && !_running ? () => _run(includeWrite: true) : null,
              child: const Text('含写入探测'),
            ),
            if (_running) ...[
              const SizedBox(height: 20),
              const LinearProgressIndicator(color: GRemoteColors.gold),
            ],
            if (_error case final String error) ...[
              const SizedBox(height: 16),
              Text(error, style: const TextStyle(color: GRemoteColors.danger)),
            ],
            if (report != null) ...[
              const SizedBox(height: 24),
              _ResultRow('WebSocket', report.webSocket.name),
              _ResultRow('写入格式', report.preferredEncoding.name),
              _ResultRow('参数列表', '${report.lists.length} 项'),
              _ResultRow('10 秒内推送', '${report.eventsInWindow} 条'),
              for (final MapEntry(:key, :value) in report.routes.entries)
                _ResultRow(key, value?.toString() ?? '失败'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(
                  text: jsonEncode({
                    'schema': 'gremote-diagnostics/1',
                    'protocolProfile': report.toJson(),
                  }),
                )),
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('复制 JSON'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
              child:
                  Text(label, style: const TextStyle(color: GRemoteColors.muted))),
          Text(value),
        ]),
      );
}
