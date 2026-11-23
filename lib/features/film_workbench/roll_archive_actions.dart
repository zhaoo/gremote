import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../../film/capture/active_roll_context.dart';
import 'companion_providers.dart';
import 'workbench_providers.dart';

final cameraArchiveStableKeyProvider = Provider<String?>((ref) {
  final connection = ref.watch(connectionControllerProvider);
  return connection is ConnectionReady
      ? connection.cameraKey ??
          ref.watch(effectiveCompanionIdentityProvider)?.instanceId
      : null;
});
final hiddenCameraRollIdsProvider = FutureProvider<Set<String>>((ref) {
  ref.watch(filmRollRevisionProvider);
  final key = ref.watch(cameraArchiveStableKeyProvider);
  return key == null
      ? <String>{}
      : ref.watch(filmRepositoryProvider).hiddenCameraRolls(key);
});

Future<bool> deleteLocalRollArchive(
    BuildContext context, WidgetRef ref, String rollId) async {
  final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
              title: const Text('删除胶卷记录？'),
              content: const Text('只删除 App 内的胶卷编排，照片和相机原片会保留。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('删除'))
              ]));
  if (confirmed != true || !context.mounted) return false;
  await ref.read(filmRepositoryProvider).deleteRollArchive(rollId);
  if (ref.read(activeRollCaptureContextProvider)?.rollId == rollId) {
    ref.read(activeRollCaptureContextProvider.notifier).state = null;
  }
  ref.read(filmRollRevisionProvider.notifier).state++;
  return true;
}

Future<bool> hideCameraRollArchive(BuildContext context, WidgetRef ref,
    String cameraKey, String rollId) async {
  final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
              title: const Text('移除胶卷记录？'),
              content: const Text('仅从这台相机的 App 列表移除，不修改相机和照片。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('移除'))
              ]));
  if (confirmed != true || !context.mounted) return false;
  await ref.read(filmRepositoryProvider).hideCameraRoll(cameraKey, rollId);
  ref.read(filmRollRevisionProvider.notifier).state++;
  return true;
}
