import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_presence.dart';
import '../../camera/companion/companion_operation_gate.dart';
import '../../camera/companion/extensions_controller.dart';
import '../../camera/companion/extensions_protocol.dart';
import '../../camera/program/program_controller.dart';
import '../../camera/program/program_runner.dart';
import '../../camera/sync/camera_state_controller.dart';
import '../../darkroom/darkroom_providers.dart';
import '../film_workbench/companion_providers.dart';
import '../library/camera_gallery.dart';

final cameraExtensionsControllerProvider =
    Provider<CameraExtensionsController?>((ref) {
  final sync = ref.watch(companionSyncControllerProvider),
      identity = ref.watch(effectiveCompanionIdentityProvider);
  if (sync == null || identity == null || sync.api is! CompanionExtensionsApi) {
    return null;
  }
  var alive = true;
  final controller = CameraExtensionsController(
    api: sync.api as CompanionExtensionsApi,
    instanceId: identity.instanceId,
    store: SqliteExtensionPendingStore(
        ref.watch(databaseProvider), identity.instanceId),
    bootstrap: () async {
      if (sync.api.bootId == null) await sync.api.capabilities();
    },
    blocked: () =>
        !ref.read(appForegroundProvider) ||
        !ref.read(companionNetworkReadyProvider) ||
        ref.read(shootPageVisibleProvider) ||
        ref.read(cameraStateControllerProvider.notifier).isCapturing ||
        {RunPhase.preparing, RunPhase.running}
            .contains(ref.read(programControllerProvider).phase) ||
        ref.read(cameraGalleryServiceProvider).transferGate.savingOriginals ||
        sync.state.pending,
    onPending: (pending) {
      if (alive) {
        ref
            .read(
                extensionMutationPendingProvider(identity.instanceId).notifier)
            .state = pending;
        ref.invalidate(extensionPendingPresenceProvider(identity.instanceId));
      }
    },
  );
  ref.listen(companionNetworkReadyProvider, (_, ready) {
    if (ready) unawaited(controller.refresh());
  });
  ref.onDispose(() {
    alive = false;
    controller.dispose();
  });
  return controller;
});
