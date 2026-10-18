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
        child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('位置记录', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('仅联机拍摄时记录'),
                      subtitle: Text(state.error ??
                          (state.active
                              ? state.fix == null
                                  ? '正在获取手机位置…'
                                  : '正在记录 · 精度约 ${state.fix!.accuracy.round()} 米'
                              : state.enabled
                                  ? '已开启，等待进入联机拍摄'
                                  : '关闭')),
                      value: state.enabled,
                      onChanged: _busy
                          ? null
                          : (value) async {
                              setState(() => _busy = true);
                              try {
                                await ref
                                    .read(locationRecordingProvider.notifier)
                                    .setEnabled(value);
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            }),
                  const Text('将手机位置关联到联机拍摄记录。退出拍摄或切到后台即停止定位，原始照片不会被改写。',
                      style: TextStyle(
                          color: GRemoteColors.muted,
                          fontSize: 12,
                          height: 1.6)),
                  const SizedBox(height: 18),
                  const Text('最近拍摄位置',
                      style: TextStyle(
                          color: GRemoteColors.goldSoft, fontSize: 13)),
                  const SizedBox(height: 8),
                  SizedBox(
                      height: 200,
                      child: history.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (_, __) =>
                              const Center(child: Text('暂时无法读取位置记录')),
                          data: (records) => records.isEmpty
                              ? const Center(child: Text('获得可靠定位后，拍摄的照片会记录在这里'))
                              : ListView.builder(
                                  itemCount: records.length,
                                  itemBuilder: (_, index) {
                                    final record = records[index];
                                    final time = record.capturedAt;
                                    return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        title: Text(record.baseName),
                                        subtitle: Text(
                                            '${record.fix.latitude.toStringAsFixed(5)}, ${record.fix.longitude.toStringAsFixed(5)} · ±${record.fix.accuracy.round()} 米'),
                                        trailing: Text(
                                            '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                            style:
                                                const TextStyle(fontSize: 11)));
                                  }))),
                ])));
  }
}
