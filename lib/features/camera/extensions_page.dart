import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../camera/companion/extensions_controller.dart';
import '../../camera/companion/extensions_protocol.dart';
import '../film_workbench/companion_providers.dart';
import 'extensions_providers.dart';
import 'camera_availability.dart';

class CameraExtensions extends ConsumerStatefulWidget {
  const CameraExtensions({super.key});
  @override
  ConsumerState<CameraExtensions> createState() => _CameraExtensionsState();
}

class _CameraExtensionsState extends ConsumerState<CameraExtensions> {
  CameraExtensionsController? _loaded;
  String? _expandedGroup;
  static const _groups = {
    '功能': Icons.toggle_on_outlined,
    '效果': Icons.auto_awesome_outlined,
    '水印': Icons.approval_outlined,
    '焦距': Icons.center_focus_weak,
    '画幅': Icons.crop_free,
  };

  @override
  Widget build(BuildContext context) {
    ref.watch(companionIdentityHydrationProvider);
    final controller = ref.watch(cameraExtensionsControllerProvider),
        connected = ref.watch(companionNetworkReadyProvider);
    if (controller != null && connected && !identical(_loaded, controller)) {
      _loaded = controller;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(controller.refresh());
      });
    }
    return controller == null
        ? _settings(null, connected)
        : ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _settings(controller, connected));
  }

  String _status(CameraExtensionsController? controller, bool connected) {
    if (!connected || controller == null) {
      return controller?.pending == true
          ? '结果待核对 · 重新连接后核对'
          : controller == null
              ? m10vServiceUnavailableHint
              : '未连接 · 连接相机后读取机身设置';
    }
    if (controller.working && controller.pending) return '设置处理中，请勿重复提交';
    if (controller.pending) {
      return controller.message ?? '结果待核对，请勿重复提交';
    }
    if (controller.working) return '正在读取机身设置…';
    if (controller.message != null) return controller.message!;
    if (controller.snapshot == null) return '尚未读取机身设置';
    if (controller.snapshot!.busy) return '机身忙碌 · 暂不可设置';
    if (!controller.canWrite) return '当前仅可查看 · 请结束拍摄、程序或原图传输后设置';
    return '设置已读取';
  }

  Widget _settings(CameraExtensionsController? controller, bool connected) {
    final available = controller != null && connected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Text(_status(controller, connected),
                style: TextStyle(color: context.palette.muted, fontSize: 12)),
          ),
          if (available)
            TextButton(
                onPressed: controller.working ? null : controller.refresh,
                child: const Text('重新读取', style: TextStyle(fontSize: 12))),
          if (!available && controller == null)
            TextButton(
                onPressed: () =>
                    ref.invalidate(companionHotspotPairingProvider),
                child: const Text('重试连接', style: TextStyle(fontSize: 12))),
        ]),
        if (available &&
            controller.working &&
            !MediaQuery.disableAnimationsOf(context))
          const LinearProgressIndicator(minHeight: 2),
        if (available && controller.pending)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: OutlinedButton(
                onPressed:
                    controller.working ? null : () => _acknowledge(controller),
                child: const Text('核对当前设置')),
          ),
        const SizedBox(height: 8),
        for (final group in _groups.entries) ...[
          ListTile(
            key: ValueKey('extension-group-${group.key}'),
            contentPadding: EdgeInsets.zero,
            minLeadingWidth: 16,
            horizontalTitleGap: 12,
            minVerticalPadding: 16,
            leading: Icon(group.value, color: context.palette.text, size: 18),
            title: Text(group.key, style: const TextStyle(fontSize: 14)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(_summary(group.key, available ? controller : null),
                  style: TextStyle(color: context.palette.muted, fontSize: 11)),
            ),
            trailing: Icon(
                _expandedGroup == group.key
                    ? Icons.keyboard_arrow_up
                    : Icons.chevron_right,
                color: context.palette.muted,
                size: 18),
            onTap: () => setState(() {
              _expandedGroup = _expandedGroup == group.key ? null : group.key;
            }),
          ),
          if (_expandedGroup == group.key)
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Column(children: [
                for (final field in extensionFields.entries
                    .where((entry) => entry.value.group == group.key))
                  _field(available ? controller : null, field.key, field.value),
                if (group.key == '功能') _half(available ? controller : null),
              ]),
            ),
          const Divider(height: 1),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 26),
          child: Text('开关机画面暂不支持远程设置',
              style: TextStyle(color: context.palette.muted, fontSize: 11)),
        ),
      ],
    );
  }

  String _summary(String group, CameraExtensionsController? controller) {
    final values = controller?.snapshot?.values;
    switch (group) {
      case '功能':
        return '快切 · Half';
      case '效果':
        return '暗角 · 胶卷印花 · HDF · 边框 · 颗粒 · 漏光 · 模糊';
      case '水印':
        return '时间 · 胶卷名';
      case '焦距':
        final a = values?['focalA'], b = values?['focalB'];
        return a != null && b != null ? '$a mm / $b mm' : '第一档 · 第二档';
      case '画幅':
        if (controller?.unsupported == true ||
            controller?.snapshot != null && !_supported(controller, 'aspect')) {
          return '此项暂不支持';
        }
        final aspect = values?['aspect'];
        return aspect == null
            ? '尚未读取'
            : extensionFields['aspect']!.display(aspect);
      default:
        return '';
    }
  }

  bool _supported(CameraExtensionsController? controller, String key) =>
      controller?.capabilities?.supported.contains(key) == true &&
      controller?.snapshot?.supported.contains(key) == true;

  bool _editable(CameraExtensionsController? controller, String key) =>
      controller != null &&
      controller.canWrite &&
      _supported(controller, key) &&
      controller.snapshot?.values[key] != null &&
      !((key == 'quickSwitchA' || key == 'quickSwitchB') &&
          controller.snapshot?.values['quickSwitch'] == 1);

  Widget _field(CameraExtensionsController? controller, String key,
      ExtensionField field) {
    final value = controller?.snapshot?.values[key];
    final supported = _supported(controller, key);
    final pairedEdit = (key == 'quickSwitchA' || key == 'quickSwitchB') &&
        controller?.snapshot?.values['quickSwitch'] == 1;
    final enabled = _editable(controller, key);
    if (key == 'vignetteEnabled') {
      return SwitchListTile(
        key: const ValueKey('extension-field-vignetteEnabled'),
        contentPadding: EdgeInsets.zero,
        title: const Text('暗角'),
        subtitle: !supported ? const Text('此项暂不支持') : null,
        value: value == 1,
        onChanged: enabled
            ? (on) => _submit(controller!, key, on ? 1 : 0,
                revision: controller.snapshot!.revision)
            : null,
      );
    }
    return ListTile(
      key: ValueKey('extension-field-$key'),
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      title: Text(field.label, style: const TextStyle(fontSize: 14)),
      subtitle: pairedEdit
          ? const Text('先关闭快切再修改配对', style: TextStyle(fontSize: 11))
          : controller?.snapshot != null && !supported
              ? const Text('此项暂不支持', style: TextStyle(fontSize: 11))
              : field.runtime
                  ? Text(key == 'quickSwitch' ? '重启后关闭' : '当前机身状态',
                      style: const TextStyle(fontSize: 11))
                  : null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .32),
            child: Text(supported && value != null ? field.display(value) : '—',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: enabled
                        ? context.palette.text
                        : context.palette.muted))),
        const SizedBox(width: 6),
        if (enabled)
          Icon(Icons.chevron_right, size: 18, color: context.palette.muted),
      ]),
      onTap: enabled ? () => _choose(controller!, key, field) : null,
    );
  }

  Widget _half(CameraExtensionsController? controller) {
    final value = controller?.snapshot?.values['aspect'];
    return ListTile(
        key: const ValueKey('extension-half'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Half', style: TextStyle(fontSize: 14)),
        subtitle: const Text('两次拍摄拼接', style: TextStyle(fontSize: 11)),
        trailing: value == null
            ? const Text('—')
            : Switch(
                value: value == 6,
                onChanged: _editable(controller, 'aspect')
                    ? (enabled) => _submit(
                        controller!, 'aspect', enabled ? 6 : 0,
                        revision: controller.snapshot!.revision)
                    : null));
  }

  Future<void> _choose(CameraExtensionsController controller, String key,
      ExtensionField field) async {
    final revision = controller.snapshot!.revision;
    final options = (field.choices?.keys.toList() ??
            [for (var i = field.min; i <= field.max; i++) i])
        .where((value) => controller.capabilities?.accepts(key, value) == true)
        .toList();
    final value = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : null,
        isScrollControlled: true,
        builder: (sheet) => ListenableBuilder(
            listenable: controller,
            builder: (sheet, _) => SafeArea(
                child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(sheet).height * .72),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(field.label,
                              style: Theme.of(sheet).textTheme.titleLarge)),
                      Flexible(
                          child: ListView(shrinkWrap: true, children: [
                        for (final value in options)
                          RadioListTile<int>(
                              title: Text(field.display(value)),
                              value: value,
                              groupValue: controller.snapshot?.values[key],
                              onChanged: _editable(controller, key) &&
                                      controller.snapshot?.revision == revision
                                  ? (value) => Navigator.pop(sheet, value)
                                  : null)
                      ]))
                    ])))));
    if (!mounted ||
        value == null ||
        value == controller.snapshot?.values[key]) {
      return;
    }
    await _submit(controller, key, value, revision: revision);
  }

  Future<void> _submit(
      CameraExtensionsController controller, String key, int value,
      {required String revision}) async {
    if (!mounted ||
        !_editable(controller, key) ||
        controller.snapshot?.revision != revision) return;
    await controller.set(key, value, expectedRevision: revision);
    if (mounted && controller.message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(controller.message!)));
    }
  }

  Future<bool?> _showConfirmationDialog({required WidgetBuilder builder}) {
    if (!MediaQuery.disableAnimationsOf(context)) {
      return showDialog<bool>(context: context, builder: builder);
    }
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: Duration.zero,
      pageBuilder: (dialog, _, __) => SafeArea(child: builder(dialog)),
    );
  }

  Future<void> _acknowledge(CameraExtensionsController controller) async {
    final confirmed = await _showConfirmationDialog(
        builder: (dialog) => AlertDialog(
                title: const Text('核对当前设置'),
                content: const Text('重新读取机身。未决操作需重启相机后再核对，不会重复提交。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('重新读取'))
                ]));
    if (confirmed == true && mounted) {
      await controller.acknowledgeCurrentState();
    }
  }
}
