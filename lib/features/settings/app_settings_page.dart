import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../platform/app_package_info.dart';

import '../../app/interaction/app_haptics.dart';
import '../../app/theme/app_palette.dart';
import '../../app/widgets/workspace_motion.dart';
import '../../settings/app_preferences.dart';
import '../../settings/preferences_controller.dart';

final appPackageInfoProvider =
    FutureProvider<AppPackageInfo>((ref) => AppPackageInfo.fromPlatform());

class AppSettingsPage extends ConsumerWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appPreferencesProvider);
    final controller = ref.read(appPreferencesProvider.notifier);
    final info = ref.watch(appPackageInfoProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.chevron_left),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('设置'),
        titleTextStyle: TextStyle(
            color: context.palette.text,
            fontSize: 20,
            fontWeight: FontWeight.w500),
        titleSpacing: 4,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(children: [
                  Expanded(
                      child: Text(state.loadFailed ? '设置读取失败，请重试' : '设置未保存，请重试',
                          style: TextStyle(
                              color: context.palette.danger, fontSize: 13))),
                  TextButton(
                      onPressed: state.saving ? null : controller.retry,
                      child: const Text('重试')),
                ]),
              ),
            const _GroupLabel('外观'),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (value, label, icon) in [
                (
                  ThemePreference.system,
                  '跟随系统',
                  Icons.brightness_auto_outlined
                ),
                (ThemePreference.dark, '深色', Icons.dark_mode_outlined),
                (ThemePreference.light, '浅色', Icons.light_mode_outlined),
              ]) ...[
                if (value != ThemePreference.system) const SizedBox(width: 10),
                Expanded(
                    child: _ThemeOption(
                  label: label,
                  icon: icon,
                  selected: state.preferences.theme == value,
                  onTap: () {
                    unawaited(controller.setTheme(value));
                    unawaited(ref.read(appHapticsProvider).selection());
                  },
                )),
              ],
            ]),
            const SizedBox(height: 38),
            const _GroupLabel('体验'),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('触感反馈', style: TextStyle(fontSize: 15)),
              value: state.preferences.haptics,
              onChanged: (value) {
                unawaited(controller.setHaptics(value));
                unawaited(ref.read(appHapticsProvider).selection());
              },
            ),
            const SizedBox(height: 26),
            const _GroupLabel('关于'),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(children: [
                const Text('版本', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 16),
                Expanded(
                    child: Align(
                  alignment: Alignment.centerRight,
                  child: info.when(
                    data: (package) => Text(
                        '${package.version} (${package.buildNumber})',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                            color: context.palette.muted, fontSize: 13)),
                    loading: () => const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1)),
                    error: (_, __) => TextButton(
                        onPressed: () => ref.invalidate(appPackageInfoProvider),
                        child: const Text('重新读取')),
                  ),
                )),
              ]),
            ),
            Divider(height: 1, color: context.palette.divider),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开源许可', style: TextStyle(fontSize: 15)),
              trailing: Icon(Icons.chevron_right,
                  size: 18, color: context.palette.muted),
              onTap: () => showLicensePage(
                  context: context,
                  applicationName: info.valueOrNull?.appName ?? 'GRemote',
                  applicationVersion: info.valueOrNull == null
                      ? null
                      : '${info.valueOrNull!.version} (${info.valueOrNull!.buildNumber})'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Text(label, style: TextStyle(color: context.palette.muted, fontSize: 12));
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        label: selected ? '$label，已选择' : label,
        selected: selected,
        button: true,
        excludeSemantics: true,
        child: AnimatedContainer(
          duration: WorkspaceMotion.duration(context, 160),
          decoration: BoxDecoration(
            color: selected ? context.palette.raised : Colors.transparent,
            border: Border.all(
                color:
                    selected ? context.palette.text : context.palette.divider),
            borderRadius: BorderRadius.circular(5),
          ),
          child: InkWell(
            enableFeedback: false,
            onTap: onTap,
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon,
                    size: 20,
                    color: selected
                        ? context.palette.text
                        : context.palette.muted),
                const SizedBox(height: 12),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        fontWeight:
                            selected ? FontWeight.w500 : FontWeight.w400,
                        color: selected
                            ? context.palette.text
                            : context.palette.muted)),
              ]),
            ),
          ),
        ),
      );
}
