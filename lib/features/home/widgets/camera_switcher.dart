import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../camera/connection/connection_state.dart';
import '../../../camera/gateway/ble_gateway.dart';

class CameraSwitcher extends StatefulWidget {
  const CameraSwitcher(
      {required this.discover,
      required this.onManualWifi,
      this.current,
      super.key});

  final Future<List<BleDeviceCandidate>> Function() discover;
  final VoidCallback onManualWifi;
  final ConnectionReady? current;

  @override
  State<CameraSwitcher> createState() => _CameraSwitcherState();
}

class _CameraSwitcherState extends State<CameraSwitcher> {
  var _scanning = false;
  String? _error;
  List<BleDeviceCandidate> _devices = const [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final devices = await widget.discover();
      if (!mounted) return;
      final currentKey = widget.current?.cameraKey;
      final seen = <String>{};
      setState(() => _devices = devices
          .where((device) =>
              seen.add(device.id) &&
              (currentKey == null ||
                  sha256.convert(utf8.encode('ble:${device.id}')).toString() !=
                      currentKey))
          .toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi)));
    } catch (_) {
      if (mounted) setState(() => _error = '扫描未完成');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  String _name(String name) => name.trim().isEmpty
      ? 'RICOH 相机'
      : name.trim().replaceFirst(RegExp(r'^RICOH\s+'), '');

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text('切换相机',
                            style: Theme.of(context).textTheme.titleLarge)),
                    IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 21)),
                  ]),
                  if (widget.current case final ConnectionReady ready) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: context.palette.raised,
                          borderRadius: BorderRadius.circular(7)),
                      child: Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(_name(ready.snapshot.identity.model),
                                  style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 7),
                              Text('已连接',
                                  style: TextStyle(
                                      color: context.palette.muted,
                                      fontSize: 12)),
                            ])),
                        const SizedBox(width: 12),
                        const Icon(Icons.check, size: 19),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(
                        child: Text('附近相机',
                            style: TextStyle(
                                fontSize: 12, color: context.palette.muted))),
                    if (_scanning)
                      const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox.square(
                              dimension: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.5)))
                    else
                      IconButton(
                          tooltip: '重新扫描',
                          onPressed: _scan,
                          icon: const Icon(Icons.refresh, size: 20)),
                  ]),
                  for (final device in _devices)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      minVerticalPadding: 14,
                      title: Text(_name(device.name)),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: _scanning
                          ? null
                          : () => Navigator.pop(context, device),
                    ),
                  if (!_scanning && _devices.isEmpty)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(_error ?? '未发现相机',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.palette.muted))),
                  const SizedBox(height: 16),
                  TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onManualWifi();
                      },
                      child: const Text('手动连接 Wi-Fi')),
                ]),
          ),
        ),
      );
}
