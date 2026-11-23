import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/theme/app_colors.dart';
import 'location_recording.dart';

class LocationControls extends ConsumerStatefulWidget {
  const LocationControls({super.key});
  @override
  ConsumerState<LocationControls> createState() => _LocationControlsState();
}

class _LocationControlsState extends ConsumerState<LocationControls> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(locationRecordingProvider);
    final history = ref.watch(shotLocationsProvider);
    return SafeArea(
        child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('位置记录',
                      style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          color: context.palette.text)),
                  const SizedBox(height: 16),
                  SwitchListTile(
                      thumbColor: WidgetStateProperty.resolveWith((states) =>
                          states.contains(WidgetState.selected)
                              ? context.palette.onAccent
                              : context.palette.text),
                      trackColor: WidgetStateProperty.resolveWith((states) =>
                          states.contains(WidgetState.selected)
                              ? context.palette.accent
                              : context.palette.divider),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('联机拍摄时记录位置',
                          style: TextStyle(fontSize: 14)),
                      subtitle: state.error != null
                          ? Text(state.error!,
                              style: TextStyle(
                                  color: context.palette.danger, fontSize: 12))
                          : state.active
                              ? Text(
                                  state.fix == null
                                      ? '正在获取位置…'
                                      : '记录中 · 精度约 ${state.fix!.accuracy.round()} 米',
                                  style: const TextStyle(fontSize: 12))
                              : state.enabled
                                  ? const Text('等待联机拍摄',
                                      style: TextStyle(fontSize: 12))
                                  : null,
                      value: state.enabled,
                      onChanged: _busy
                          ? null
                          : (enabled) async {
                              setState(() => _busy = true);
                              try {
                                await ref
                                    .read(locationRecordingProvider.notifier)
                                    .setEnabled(enabled);
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            }),
                  const SizedBox(height: 8),
                  Text('仅联机拍摄时定位，不改写照片。',
                      style: TextStyle(
                          color: context.palette.muted, fontSize: 12)),
                  const SizedBox(height: 24),
                  history.when(
                      loading: () =>
                          const LinearProgressIndicator(minHeight: 2),
                      error: (_, __) => Text('位置记录暂时无法读取',
                          style: TextStyle(
                              color: context.palette.muted, fontSize: 12)),
                      data: (records) => records.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text('暂无拍摄位置',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: context.palette.muted,
                                      fontSize: 12)))
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  Text('最近拍摄',
                                      style: TextStyle(
                                          color: context.palette.muted,
                                          fontSize: 12)),
                                  const SizedBox(height: 10),
                                  ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxHeight: 240),
                                      child: ListView.builder(
                                          shrinkWrap: true,
                                          itemCount: records.length,
                                          itemBuilder: (_, i) {
                                            final record = records[i],
                                                time = record.capturedAt;
                                            return ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                dense: true,
                                                title: Text(record.baseName),
                                                subtitle: Text(
                                                    '${record.fix.latitude.toStringAsFixed(5)}, ${record.fix.longitude.toStringAsFixed(5)} · ±${record.fix.accuracy.round()} 米'),
                                                trailing: Text(
                                                    '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                                    style: const TextStyle(
                                                        fontSize: 11)));
                                          }))
                                ])),
                ])));
  }
}
