import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_type.dart';
import '../../../camera/connection/connection_state.dart';

class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    required this.state,
    required this.onConnect,
    required this.onRetry,
    required this.onSelectDevice,
    required this.onEnterShoot,
    required this.onOpenDiagnostics,
    this.onManualWifi,
    this.onCancel,
    super.key,
  });

  final CameraConnectionState state;
  final VoidCallback onConnect;
  final VoidCallback onRetry;
  final ValueChanged<String> onSelectDevice;
  final VoidCallback onEnterShoot;
  final VoidCallback onOpenDiagnostics;
  final VoidCallback? onManualWifi;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return GestureDetector(
      onLongPress: onOpenDiagnostics,
      child: Theme(
        data: Theme.of(context).copyWith(
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE1E5E3),
                  foregroundColor: const Color(0xFF181C1D),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)))),
          textButtonTheme: TextButtonThemeData(
              style:
                  TextButton.styleFrom(foregroundColor: GRemoteColors.muted)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            child: _content(context),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (state case final ConnectionReady ready) {
      return _ReadyContent(
        key: const ValueKey('ready'),
        state: ready,
        onEnterShoot: onEnterShoot,
      );
    }
    if (state case final ConnectionFailed failed) {
      return _FailureContent(
        key: const ValueKey('failed'),
        failure: failed.failure,
        onRetry: onRetry,
        onOpenDiagnostics: onOpenDiagnostics,
        onManualWifi: onManualWifi,
      );
    }
    if (state case final ConnectionDeviceChoice choice) {
      return _ChoiceContent(
        key: const ValueKey('choice'),
        state: choice,
        onSelectDevice: onSelectDevice,
      );
    }

    final presentation = _presentation(state);
    return Column(
      key: ValueKey(state.stage),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CameraSummary(
          status: presentation.status,
          title: presentation.title,
          detail: presentation.detail,
        ),
        const SizedBox(height: 12),
        if (state is ConnectionIdle)
          Column(children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.bluetooth_searching, size: 18),
                label: const Text('连接相机'),
              ),
            ),
            if (onManualWifi != null)
              TextButton(
                onPressed: onManualWifi,
                child: const Text('手动连接 Wi-Fi'),
              ),
          ])
        else ...[
          const SizedBox(
            height: 3,
            child: LinearProgressIndicator(
              backgroundColor: GRemoteColors.divider,
              color: GRemoteColors.gold,
            ),
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onCancel, child: const Text('取消连接')),
          ],
        ],
      ],
    );
  }

  _ConnectionPresentation _presentation(CameraConnectionState state) =>
      switch (state) {
        ConnectionIdle() => const _ConnectionPresentation(
            status: '未连接',
            title: '连接相机',
            detail: '通过蓝牙或相机 Wi-Fi 连接。',
          ),
        ConnectionPermissions() => const _ConnectionPresentation(
            status: '权限',
            title: '正在确认连接权限',
            detail: '首次连接需要附近设备或定位权限，请在系统提示中允许。',
          ),
        ConnectionScanning() => const _ConnectionPresentation(
            status: 'BLE',
            title: '正在扫描附近相机',
            detail: '保持相机蓝牙开启，并将手机靠近相机。',
          ),
        ConnectionPairing() => const _ConnectionPresentation(
            status: '配对',
            title: '正在建立安全连接',
            detail: '请确认相机与系统显示的配对提示。',
          ),
        ConnectionBleReady() => const _ConnectionPresentation(
            status: 'BLE 就绪',
            title: '已读取相机身份',
            detail: '正在准备唤醒相机。',
          ),
        ConnectionWaking() => const _ConnectionPresentation(
            status: '唤醒',
            title: '正在唤醒相机',
            detail: '请勿关闭相机电源。',
          ),
        ConnectionApStarting() => const _ConnectionPresentation(
            status: '热点',
            title: '正在开启相机热点',
            detail: '相机正在切换到无线连接模式。',
          ),
        ConnectionWifiRequesting() ||
        ConnectionWifiManualRequesting() =>
          const _ConnectionPresentation(
            status: 'Wi-Fi',
            title: '正在连接相机 Wi-Fi',
            detail: '请确认相机“无线 LAN”已开启（仅开启蓝牙还不够）。如出现系统连接提示，请选择允许；已允许后请等待连接。',
          ),
        ConnectionWifiBound() => const _ConnectionPresentation(
            status: 'Wi-Fi 已绑定',
            title: '正在确认相机地址',
            detail: '仅相机请求会通过这个无互联网网络。',
          ),
        ConnectionProbing() => const _ConnectionPresentation(
            status: '协议探测',
            title: '正在读取相机能力',
            detail: '检查原厂 HTTP API 与实时取景能力。',
          ),
        _ => const _ConnectionPresentation(
            status: '连接中',
            title: '正在准备相机',
            detail: '请稍候。',
          ),
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) => Row(children: [
        const Expanded(
            child: Text('相机连接',
                style: TextStyle(fontSize: 12, color: GRemoteColors.muted))),
        Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: status == '连接中断'
                    ? GRemoteColors.danger
                    : status == '已连接'
                        ? GRemoteColors.text
                        : GRemoteColors.muted)),
        const SizedBox(width: 6),
        Flexible(
            child: Text(status,
                style:
                    const TextStyle(fontSize: 12, color: GRemoteColors.muted))),
      ]);
}

class _CameraIdentity extends StatelessWidget {
  const _CameraIdentity({this.model = 'RICOH GR III'});
  final String model;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Semantics(
                label: model,
                child: ExcludeSemantics(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      if (model.startsWith('RICOH '))
                        const Text('RICOH',
                            style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 1.9,
                                color: GRemoteColors.muted)),
                      const SizedBox(height: 5),
                      Text(model.replaceFirst(RegExp(r'^RICOH '), ''),
                          style: GRemoteType.display
                              .copyWith(fontSize: 33, letterSpacing: -.8)),
                    ])))),
        const SizedBox(width: 8),
        if (model == 'RICOH GR III')
          Flexible(
              child: Image.asset('assets/images/gr_compact_camera.png',
                  width: 150,
                  height: 112,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true)),
      ]);
}

class _CameraSummary extends StatelessWidget {
  const _CameraSummary(
      {required this.status, required this.title, required this.detail});
  final String status, title, detail;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Header(status: status),
        const SizedBox(height: 8),
        const _CameraIdentity(),
        if (title != '连接相机') ...[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          Text(detail,
              style: const TextStyle(fontSize: 12, color: GRemoteColors.muted)),
        ],
      ]);
}

class _ReadyContent extends StatelessWidget {
  const _ReadyContent({
    required this.state,
    required this.onEnterShoot,
    super.key,
  });

  final ConnectionReady state;
  final VoidCallback onEnterShoot;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header(status: '已连接'),
        const SizedBox(height: 18),
        _CameraIdentity(model: snapshot.identity.model),
        const SizedBox(height: 12),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            const Text('Wi-Fi',
                style: TextStyle(fontSize: 12, color: GRemoteColors.muted)),
            _Fact(
              label: '固件',
              value: snapshot.identity.firmware.isEmpty
                  ? '未读取'
                  : snapshot.identity.firmware,
            ),
            if (!state.wifiOnly || snapshot.battery.level >= 0) ...[
              _Fact(label: '电量', value: '${snapshot.battery.level}%'),
            ],
          ],
        ),
        if (state.wifiOnly && snapshot.identity.firmware.isEmpty) ...[
          const SizedBox(height: 14),
          const Text('Wi-Fi 属性未提供固件版本；可用蓝牙连接核验',
              style: TextStyle(color: GRemoteColors.goldSoft)),
        ] else if (state.firmwareWarning) ...[
          const SizedBox(height: 14),
          const Text(
            '固件未经真机验证',
            style: TextStyle(color: GRemoteColors.goldSoft),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onEnterShoot,
            icon: const Icon(Icons.center_focus_strong),
            label: const Text('进入拍摄'),
          ),
        ),
      ],
    );
  }
}

class _ChoiceContent extends StatelessWidget {
  const _ChoiceContent({
    required this.state,
    required this.onSelectDevice,
    super.key,
  });

  final ConnectionDeviceChoice state;
  final ValueChanged<String> onSelectDevice;

  @override
  Widget build(BuildContext context) {
    final strongest = state.devices.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header(status: '请选择'),
        const SizedBox(height: 17),
        Text('发现 ${state.devices.length} 台相机',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('优先连接信号最强的 ${strongest.name}，设备地址不会显示。'),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => onSelectDevice(strongest.id),
            child: Text('连接 ${strongest.name}'),
          ),
        ),
      ],
    );
  }
}

class _FailureContent extends StatelessWidget {
  const _FailureContent({
    required this.failure,
    required this.onRetry,
    required this.onOpenDiagnostics,
    this.onManualWifi,
    super.key,
  });

  final ConnectionFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onOpenDiagnostics;
  final VoidCallback? onManualWifi;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CameraSummary(
            status: '连接中断',
            title: _failureTitle(failure.code),
            detail: _failureGuidance(failure),
          ),
          if (failure.retryable) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(
                  failure.userAction == ConnectionUserAction.openSettings
                      ? '打开设置'
                      : '重新连接',
                ),
              ),
            ),
          ],
          if (onManualWifi != null)
            Center(
              child: TextButton(
                onPressed: onManualWifi,
                child: const Text('手动连接 Wi-Fi'),
              ),
            ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: onOpenDiagnostics,
              style: TextButton.styleFrom(
                  foregroundColor: GRemoteColors.goldSoft,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('查看连接诊断',
                  style: TextStyle(
                      fontSize: 10, decoration: TextDecoration.underline)),
            ),
          ),
        ],
      );

  String _failureTitle(String code) => switch (code) {
        'cameraNotFound' => '未找到相机',
        'unsupportedCamera' => '暂不支持这台相机',
        'wifiUserRejected' => '需要允许 Wi-Fi 连接',
        'wifiTimeout' => '相机 Wi-Fi 连接超时',
        'bleTimeout' => '蓝牙读取超时',
        'bleDisconnected' => '蓝牙连接中断',
        'wifiLost' => '相机 Wi-Fi 已断开',
        'permissionDenied' => '缺少连接权限',
        'permissionPermanentlyDenied' => '需要在系统设置中授权',
        _ => '连接没有完成',
      };

  String _failureGuidance(ConnectionFailure failure) =>
      failure.code == 'wifiTimeout'
          ? '请在相机中开启“无线 LAN”；蓝牙开启不代表 Wi-Fi 已开启。开启后重新连接，并允许系统连接提示。'
          : failure.code == 'cameraNotFound'
              ? '请确认相机已开启并靠近手机。'
              : switch (failure.userAction) {
                  ConnectionUserAction.openSettings => '打开系统设置授予权限，然后返回重试。',
                  ConnectionUserAction.confirmWifi => '重试后请在系统弹窗中选择“允许”。',
                  ConnectionUserAction.retry => '确认相机已开启，然后从失败步骤重试。',
                  _ => '请查看支持范围或稍后重试。',
                };
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text('$label $value',
      style: const TextStyle(fontSize: 12, color: GRemoteColors.muted));
}

class _ConnectionPresentation {
  const _ConnectionPresentation({
    required this.status,
    required this.title,
    required this.detail,
  });

  final String status;
  final String title;
  final String detail;
}
