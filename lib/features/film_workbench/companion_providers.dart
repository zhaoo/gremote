import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_presence.dart';
import '../../camera/companion/companion_client.dart';
import '../../camera/companion/companion_transport.dart';
import '../../camera/companion/pairing_store.dart';
import '../../camera/companion/companion_sync_controller.dart';
import '../../camera/connection/connection_controller.dart';
import '../../camera/connection/connection_state.dart';
import '../../camera/sync/camera_state_controller.dart';
import '../../camera/program/program_controller.dart';
import '../../camera/program/program_runner.dart';
import '../../film/store/sync_repository.dart';
import '../../darkroom/darkroom_providers.dart';
import '../../platform/device_api.g.dart';
import '../library/camera_gallery.dart';
import 'workbench_providers.dart';

final companionPairingStoreProvider =
    Provider<PairingStore>((ref) => NativePairingStore());
final companionIdentityStorageProvider =
    Provider((ref) => PairingIdentityStorage());
final companionPairingIdentityProvider =
    StateProvider<PairingIdentity?>((ref) => null);
final companionIdentityHydrationProvider = FutureProvider<void>((ref) async {
  var alive = true;
  ref.onDispose(() => alive = false);
  final loaded = await ref.read(companionIdentityStorageProvider).read();
  if (alive && ref.read(companionPairingIdentityProvider) == null) {
    ref.read(companionPairingIdentityProvider.notifier).state = loaded;
  }
});
final companionFilePickerProvider =
    Provider<Future<Uint8List?> Function(String)>(
        (ref) => CameraDeviceHostApi().pickCompanionFile);
final companionApiFactoryProvider =
    Provider<CompanionApi Function(PairingIdentity)>((ref) {
  final keys = ref.watch(companionPairingStoreProvider);
  return (identity) => CompanionClient(
      transport: NativeCompanionTransport(),
      pairingStore: keys,
      identity: identity);
});
final companionNetworkReadyProvider = Provider<bool>((ref) {
  if (ref.watch(companionPairingIdentityProvider) == null) return false;
  return ref.watch(connectionControllerProvider) is ConnectionReady;
});
final companionSyncControllerProvider =
    Provider.autoDispose<CompanionSyncController?>((ref) {
  final identity = ref.watch(companionPairingIdentityProvider),
      catalog = ref.watch(filmCatalogProvider).valueOrNull;
  if (identity == null || catalog == null) return null;
  final api = ref.watch(companionApiFactoryProvider)(identity);
  final controller = CompanionSyncController(
      api: api,
      repository: SyncRepository(ref.watch(databaseProvider)),
      catalogHash: catalog.hash,
      rendererHash: catalog.rendererHash,
      isWriteBlocked: () =>
          !ref.read(appForegroundProvider) ||
          !ref.read(companionNetworkReadyProvider) ||
          ref.read(shootPageVisibleProvider) ||
          ref.read(cameraStateControllerProvider.notifier).isCapturing ||
          {RunPhase.preparing, RunPhase.running}
              .contains(ref.read(programControllerProvider).phase) ||
          ref.read(cameraGalleryServiceProvider).transferGate.savingOriginals,
      keepLocalRecipe: (recipe) =>
          ref.read(filmRepositoryProvider).saveRecipe(recipe));
  ref.listen(companionNetworkReadyProvider, (_, ready) {
    if (!ready) controller.disconnected();
  });
  ref.onDispose(controller.dispose);
  return controller;
});
