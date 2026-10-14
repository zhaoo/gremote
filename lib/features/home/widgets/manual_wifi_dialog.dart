import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../../app/theme/app_colors.dart';
import '../../../platform/nearby_wifi_scanner.dart';

class ManualWifiDialog extends StatefulWidget {
  const ManualWifiDialog({this.scanner, super.key});

  final NearbyWifiScanner? scanner;

  @override
  State<ManualWifiDialog> createState() => _ManualWifiDialogState();
}

class _ManualWifiDialogState extends State<ManualWifiDialog> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  String? _scanError;
  String? _scanNote;
  String? _selected;
  bool _manual = false;
  bool _scanning = false;
  List<NearbyWifi> _networks = const [];
  late final NearbyWifiScanner _scanner =
      widget.scanner ?? NativeNearbyWifiScanner();

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    try {
      final result = await _scanner.scan();
      if (!mounted) return;
      setState(() {
        _networks = result.networks;
        if (!_networks.any((network) => network.ssid == _selected)) {
          _selected = null;
        }
        _scanNote = result.networks.isEmpty
            ? '没有发现网络，请确认相机热点已开启，或手动输入网络名称。'
            : result.fresh
                ? null
                : '系统暂未更新扫描，显示最近发现的网络；可稍后刷新。';
        _manual = false;
      });
    } catch (error) {
      if (!mounted) return;
      final code = error is PlatformException ? error.code : '';
      setState(() => _scanError = switch (code) {
            'locationPermissionDenied' => '扫描需要精确位置权限；可在系统设置中授权，或手动输入网络名称。',
            'locationDisabled' => '请开启手机系统定位开关后重新扫描。',
            'wifiDisabled' => '请先开启手机 Wi-Fi。',
            _ => '暂时无法扫描，可重试或手动输入网络名称。',
          });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final ssid = _manual ? _ssid.text : _selected ?? '';
    final password = _password.text;
    if (ssid.trim().isEmpty ||
        utf8.encode(ssid).length > 32 ||
        password.length < 8 ||
        password.length > 63) {
      setState(() => _error = '请选择网络或填写名称（最多 32 字节），密码需为 8–63 字符。');
      return;
    }
    Navigator.pop(context, (ssid, password));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('连接 GR III Wi-Fi'),
        content: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('先开启相机“无线 LAN”，扫描并选择网络；密码可从相机“通信信息”查看。'),
            const SizedBox(height: 10),
            const Text('Android 扫描需要位置权限及定位开关，仅用于列出附近网络。',
                style: TextStyle(fontSize: 11, color: GRemoteColors.muted)),
            TextButton.icon(
                onPressed: _scanning ? null : _scan,
                icon: const Icon(Icons.refresh),
                label: Text(_scanning
                    ? '正在扫描…'
                    : _networks.isEmpty
                        ? '扫描附近 Wi-Fi'
                        : '刷新附近 Wi-Fi')),
            if (_scanning) const LinearProgressIndicator(),
            if (_scanError != null) ...[
              Text(_scanError!,
                  style: const TextStyle(color: GRemoteColors.danger)),
              if (_scanError!.contains('精确位置'))
                const TextButton(
                    onPressed: ph.openAppSettings, child: Text('打开系统设置')),
            ],
            if (_scanNote != null)
              Text(_scanNote!,
                  style: const TextStyle(
                      color: GRemoteColors.muted, fontSize: 11)),
            if (_networks.isNotEmpty && !_manual)
              SizedBox(
                  height: 140,
                  width: 280,
                  child: ListView(children: [
                    for (final network in _networks)
                      ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(network.ssid == _selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked),
                          title: Text(network.ssid,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(network.rssi >= -55
                              ? '信号强'
                              : network.rssi >= -70
                                  ? '信号中等'
                                  : '信号较弱'),
                          onTap: _scanning
                              ? null
                              : () => setState(() {
                                    _selected = network.ssid;
                                    _error = null;
                                  })),
                  ])),
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    onPressed: _scanning
                        ? null
                        : () => setState(() {
                              _manual = !_manual;
                              _error = null;
                            }),
                    child: Text(_manual ? '返回选择网络' : '手动输入网络名称'))),
            const SizedBox(height: 12),
            if (_manual)
              TextField(
                  controller: _ssid,
                  decoration: const InputDecoration(labelText: 'SSID')),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
            if (_error != null)
              Text(_error!,
                  style: const TextStyle(color: GRemoteColors.danger)),
          ],
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: _scanning ? null : _submit, child: const Text('连接')),
        ],
      );
}
