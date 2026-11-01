import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../camera/companion/extensions_controller.dart';
import '../../camera/companion/extensions_protocol.dart';
import '../film_workbench/companion_providers.dart';
import 'extensions_providers.dart';
import '../film_workbench/camera_films_page.dart';

Widget _pairingPage() => Scaffold(
    appBar: AppBar(title: const Text('机内胶卷')),
    body: const SafeArea(child: CameraFilmsPage()));

class CameraExtensions extends ConsumerStatefulWidget {
  const CameraExtensions({super.key});
  @override
  ConsumerState<CameraExtensions> createState() => _CameraExtensionsState();
}

class _CameraExtensionsState extends ConsumerState<CameraExtensions> {
  CameraExtensionsController? _loaded;
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
    if (controller == null || !connected) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.camera_outlined,
                    size: 36, color: GRemoteColors.muted),
                const SizedBox(height: 16),
                Text(controller == null ? '连接并配对 M10V 相机' : '未连接相机'),
                const SizedBox(height: 20),
                FilledButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('连接相机')),
                TextButton(
                    onPressed: () => Navigator.of(context, rootNavigator: true)
                        .push(MaterialPageRoute<void>(
                            builder: (_) => _pairingPage())),
                    child: const Text('配对与机内胶卷')),
              ])));
    }
    return ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(
                            controller.snapshot == null ? '机身设置' : 'GR III',
                            style: Theme.of(context).textTheme.titleMedium)),
                    IconButton(
                        tooltip: '读取机身设置',
                        onPressed:
                            controller.working ? null : controller.refresh,
                        icon: const Icon(Icons.refresh))
                  ]),
                  if (controller.working)
                    const LinearProgressIndicator(minHeight: 2),
                  if (controller.message != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(controller.message!,
                            style: TextStyle(
                                color: controller.pending
                                    ? GRemoteColors.gold
                                    : GRemoteColors.muted))),
                  if (controller.pending)
                    OutlinedButton(
                        onPressed: controller.working
                            ? null
                            : () => _acknowledge(controller),
                        child: const Text('核对当前设置')),
                  if (controller.unsupported)
                    Card(
                        child: ListTile(
                            title: const Text('扩展需要新版固件与 SD 服务'),
                            subtitle: const Text('胶卷读取和装卷仍可使用'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                Navigator.of(context, rootNavigator: true).push(
                                    MaterialPageRoute<void>(
                                        builder: (_) => _pairingPage())))),
                  for (final group in ['功能', '效果', '水印', '焦距', '画幅']) ...[
                    Padding(
                        padding: const EdgeInsets.only(top: 24, bottom: 8),
                        child: Text(group,
                            style: Theme.of(context).textTheme.titleMedium)),
                    Card(
                        child: Column(children: [
                      for (final field in extensionFields.entries
                          .where((e) => e.value.group == group))
                        _field(controller, field.key, field.value)
                    ])),
                    if (group == '功能') _half(controller),
                  ],
                  Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 8),
                      child: Text('开关机画面',
                          style: Theme.of(context).textTheme.titleMedium)),
                  const Card(
                      child: ListTile(
                          title: Text('开机 / 关机画面'),
                          subtitle: Text('需制作固件并重启，暂不支持无线替换'),
                          trailing: Icon(Icons.lock_outline, size: 18))),
                ]));
  }

  Widget _field(
      CameraExtensionsController controller, String key, ExtensionField field) {
    final value = controller.snapshot?.values[key];
    final supported =
        controller.capabilities?.supported.contains(key) == true &&
            controller.snapshot?.supported.contains(key) == true;
    final pairedEdit = (key == 'quickSwitchA' || key == 'quickSwitchB') &&
        controller.snapshot?.values['quickSwitch'] == 1;
    return ListTile(
      title: Text(field.label),
      subtitle: pairedEdit
          ? const Text('先关闭快切再修改配对', style: TextStyle(fontSize: 11))
          : field.runtime
              ? Text(key == 'quickSwitch' ? '重启后关闭' : '当前机身状态',
                  style: const TextStyle(fontSize: 11))
              : null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .38),
            child: Text(
                supported && value != null ? field.display(value) : '未开放',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color:
                        supported ? GRemoteColors.gold : GRemoteColors.muted))),
        const SizedBox(width: 6),
        Icon(supported ? Icons.chevron_right : Icons.lock_outline,
            size: 18, color: GRemoteColors.muted),
      ]),
      onTap: supported && controller.canWrite && value != null && !pairedEdit
          ? () => _choose(controller, key, field, value)
          : null,
    );
  }

  Widget _half(CameraExtensionsController controller) {
    final value = controller.snapshot?.values['aspect'];
    return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: const Text('Half'),
        subtitle: const Text('两次拍摄拼接'),
        trailing: Switch(
            value: value == 6,
            onChanged: controller.canWrite &&
                    value != null &&
                    controller.capabilities?.supported.contains('aspect') ==
                        true
                ? (enabled) => _confirm(controller, 'aspect', enabled ? 6 : 0)
                : null));
  }

  Future<void> _choose(CameraExtensionsController controller, String key,
      ExtensionField field, int current) async {
    final options = field.choices?.keys.toList() ??
        [for (var i = field.min; i <= field.max; i++) i];
    final value = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
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
                          groupValue: current,
                          onChanged: (value) => Navigator.pop(sheet, value))
                  ]))
                ]))));
    if (!mounted || value == null || value == current) return;
    await _confirm(controller, key, value);
  }

  Future<void> _confirm(
      CameraExtensionsController controller, String key, int value) async {
    final field = extensionFields[key]!;
    final revision = controller.snapshot!.revision;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text(field.label),
                content: Text(
                    '${field.display(controller.snapshot!.values[key]!)} → ${field.display(value)}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('保存'))
                ]));
    if (confirmed == true && mounted) {
      await controller.set(key, value, expectedRevision: revision);
      if (mounted && controller.message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(controller.message!)));
      }
    }
  }

  Future<void> _acknowledge(CameraExtensionsController controller) async {
    final confirmed = await showDialog<bool>(
        context: context,
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
