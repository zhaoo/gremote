import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../camera/companion/companion_protocol.dart';
import '../../camera/companion/sync_state.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../film_workbench/companion_providers.dart';

const m10vServiceUnavailableHint =
    '未连接 M10V 服务 · 请检查配套 SD 服务与脚本是否已启用';

/// Presentation policy over authenticated, current-session evidence.
/// Missing pairing and service timeouts never establish stock firmware.
class CameraAvailability {
  const CameraAvailability(
      {required this.canReadFilms,
      required this.canInstallFilms,
      required this.hint,
      this.snapshot});
  final bool canReadFilms, canInstallFilms;
  final String hint;
  final CompanionSnapshot? snapshot;

  factory CameraAvailability.fromState(
      {required bool connected,
      required bool paired,
      CompanionSyncState? sync,
      String? expectedInstanceId}) {
    final caps = sync?.capabilities, snapshot = sync?.snapshot;
    final ready = connected &&
        paired &&
        caps != null &&
        snapshot != null &&
        !sync!.stale &&
        snapshot.fresh &&
        caps.supports('readState') &&
        snapshot.instanceId == caps.instanceId &&
        snapshot.bootId == caps.bootId &&
        (expectedInstanceId == null || caps.instanceId == expectedInstanceId) &&
        {SyncConnectionStatus.ready, SyncConnectionStatus.busy}
            .contains(sync.connectionStatus);
    // Bundled camera films need writeState; uploadFilm is only for new GRF data.
    final writable = ready &&
        sync.connectionStatus == SyncConnectionStatus.ready &&
        !sync.readOnly &&
        !sync.pending &&
        !snapshot.busy &&
        caps.supports('writeState');
    final hint = !connected
        ? '连接相机后装卷'
        : !paired
            ? m10vServiceUnavailableHint
            : sync?.pending == true
                ? '装卷结果待核对'
                : sync?.connectionStatus == SyncConnectionStatus.connecting
                    ? '正在读取机内配置'
                    : !ready
                        ? '机内服务未就绪 · 仅可预览'
                        : !writable
                            ? '当前机身暂不可写入 · 仅可预览'
                            : '';
    return CameraAvailability(
        canReadFilms: ready,
        canInstallFilms: writable,
        hint: hint,
        snapshot: ready ? snapshot : null);
  }
}

final cameraAvailabilityProvider =
    Provider.autoDispose<CameraAvailability>((ref) {
  final connected = ref.watch(connectionControllerProvider) is ConnectionReady;
  final identity = ref.watch(effectiveCompanionIdentityProvider);
  final controller = ref.watch(companionSyncControllerProvider);
  void changed() => ref.invalidateSelf();
  controller?.addListener(changed);
  ref.onDispose(() => controller?.removeListener(changed));
  return CameraAvailability.fromState(
      connected: connected,
      paired: identity != null,
      sync: controller?.state,
      expectedInstanceId: identity?.instanceId);
});
