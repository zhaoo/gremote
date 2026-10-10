import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

class ManualWifiDialog extends StatefulWidget {
  const ManualWifiDialog({super.key});

  @override
  State<ManualWifiDialog> createState() => _ManualWifiDialogState();
}

class _ManualWifiDialogState extends State<ManualWifiDialog> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final ssid = _ssid.text.trim();
    final password = _password.text;
    if (ssid.isEmpty ||
        ssid.length > 32 ||
        password.length < 8 ||
        password.length > 63) {
      setState(() => _error = 'SSID 需为 1–32 字符，密码需为 8–63 字符。');
      return;
    }
    Navigator.pop(context, (ssid, password));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('手动连接 GR III Wi-Fi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('先在相机的“无线 LAN 设置”中开启热点，再从“通信信息”查看 SSID 和密码。'),
            const SizedBox(height: 12),
            TextField(
                controller: _ssid,
                decoration: const InputDecoration(labelText: 'SSID')),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: GRemoteColors.danger)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: _submit, child: const Text('连接')),
        ],
      );
}
