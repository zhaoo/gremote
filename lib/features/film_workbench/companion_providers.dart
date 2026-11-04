import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../../camera/companion/camera_film_catalog.dart';
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
import '../../camera/companion/companion_operation_gate.dart';

/// Bundled current profile is independent of the connected controller.
final latestBundledCameraCatalogProvider = FutureProvider<CameraFilmCatalog>(
    (ref) async => CameraFilmCatalog.fromJson(jsonDecode(
            await rootBundle.loadString('assets/films/camera-catalog.json'))
        as Map<String, dynamic>));
final bundledCameraCatalogsProvider =
    FutureProvider<List<CameraFilmCatalog>>((ref) async {
  final latest = await ref.watch(latestBundledCameraCatalogProvider.future);
  final installed = CameraFilmCatalog.fromJson(jsonDecode(
          await rootBundle.loadString(
              'assets/films/camera-profiles/installed-03db1c70-catalog.json'))
      as Map<String, dynamic>);
  return List.unmodifiable([latest, installed]);
});

/// UI selection follows the authenticated camera profile. Disconnected/unknown
/// cameras remain protected by controller readOnly/stale guards.
final cameraFilmCatalogProvider =
    FutureProvider<CameraFilmCatalog>((ref) async {
  final controller = ref.watch(companionSyncControllerProvider);
  if (controller != null) {
    void changed() => ref.invalidateSelf();
    controller.addListener(changed);
    ref.onDispose(() => controller.removeListener(changed));
    if (controller.cameraCatalog != null) return controller.cameraCatalog!;
  }
  return ref.watch(latestBundledCameraCatalogProvider.future);
});

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
final companionHotspotTransportProvider =
    Provider<CompanionTransport>((ref) => NativeCompanionTransport());

final _hotspotPairingProvider =
    FutureProvider<({PairingIdentity identity, HotspotPairingStore keys})?>(
        (ref) async {
  final connection = ref.watch(connectionControllerProvider.select((value) =>
      value is ConnectionReady ? (true, value.cameraKey) : (false, null)));
  if (!connection.$1) return null;
  var linked = false;
  ref.listen(appForegroundProvider, (_, foreground) {
    if (foreground && !linked) ref.invalidateSelf();
  });
  if (!ref.read(appForegroundProvider)) return null;

  final keys = HotspotPairingStore();
  final transport = ref.watch(companionHotspotTransportProvider);
  var alive = true;
  Timer? retry;
  Completer<void>? pause;
  ref.onDispose(() {
    alive = false;
    retry?.cancel();
    final pending = pause;
    if (pending != null && !pending.isCompleted) pending.complete();
    keys.clear();
  });
  for (final delay in [0, 1, 2, 4]) {
    if (delay != 0) {
      final next = pause = Completer<void>();
      retry = Timer(Duration(seconds: delay), next.complete);
      await next.future;
      if (!alive || !ref.read(appForegroundProvider)) return null;
    }
    try {
      final response = await transport.request(
          method: 'GET',
          path: '/m10v/v1/hotspot',
          body: Uint8List(0),
          headers: const {'X-M10V-Hotspot': '1'});
      if (!alive || response.statusCode == 401 || response.statusCode == 404) {
        return null; // Legacy service.
      }
      if (response.statusCode != 200) continue;
      final identity = await importPairing(response.body, keys);
      if (!alive) {
        keys.clear();
        return null;
      }
      linked = true;
      return (identity: identity, keys: keys);
    } on PlatformException catch (e) {
      if (!alive ||
          {
            'companionUnsupported',
            'invalidCompanionTarget',
            'companionSessionChanged'
          }.contains(e.code)) return null;
    } on MissingPluginException {
      return null;
    } on Exception {
      return null;
    }
  }
  if (alive) retry = Timer(const Duration(seconds: 20), ref.invalidateSelf);
  return null;
});

final effectiveCompanionIdentityProvider = Provider<PairingIdentity?>((ref) {
  final automatic = ref.watch(_hotspotPairingProvider);
  final legacy = ref.watch(companionPairingIdentityProvider);
  // A previously imported file may target a different camera. First give the
  // current connection a chance to advertise its own identity.
  return automatic.isLoading
      ? null
      : automatic.asData?.value?.identity ?? legacy;
});

final companionFilePickerProvider =
    Provider<Future<Uint8List?> Function(String)>(
        (ref) => CameraDeviceHostApi().pickCompanionFile);
final companionApiFactoryProvider =
    Provider<CompanionApi Function(PairingIdentity)>((ref) {
  final keys = ref.watch(companionPairingStoreProvider);
  final automatic = ref.watch(_hotspotPairingProvider).asData?.value;
  return (identity) => CompanionClient(
      transport: NativeCompanionTransport(),
      pairingStore:
          identical(automatic?.identity, identity) ? automatic!.keys : keys,
      identity: identity,
      contract: cameraContract);
});
final companionNetworkReadyProvider = Provider<bool>((ref) {
  if (ref.watch(effectiveCompanionIdentityProvider) == null) return false;
  return ref.watch(connectionControllerProvider) is ConnectionReady;
});
final companionSyncControllerProvider =
    Provider.autoDispose<CompanionSyncController?>((ref) {
  final identity = ref.watch(effectiveCompanionIdentityProvider),
      catalogs = ref.watch(bundledCameraCatalogsProvider).valueOrNull;
  if (identity == null || catalogs == null) return null;
  final catalog = catalogs.first;
  final api = ref.watch(companionApiFactoryProvider)(identity);
  final controller = CompanionSyncController(
      api: api,
      repository: SyncRepository(ref.watch(databaseProvider)),
      catalogHash: catalog.hash,
      rendererHash: catalog.rendererHash,
      cameraCatalog: catalog,
      resolveCameraCatalog: (caps) {
        for (final candidate in catalogs) {
          if (candidate.hash == caps.catalogHash &&
              candidate.rendererHash == caps.rendererHash) return candidate;
        }
        return null;
      },
      isWriteBlocked: () =>
          ref.read(extensionMutationPendingProvider(identity.instanceId)) ||
          ref
                  .read(extensionPendingPresenceProvider(identity.instanceId))
                  .valueOrNull !=
              false ||
          !ref.read(appForegroundProvider) ||
          !ref.read(companionNetworkReadyProvider) ||
          ref.read(shootPageVisibleProvider) ||
          ref.read(cameraStateControllerProvider.notifier).isCapturing ||
          {RunPhase.preparing, RunPhase.running}
              .contains(ref.read(programControllerProvider).phase) ||
          ref.read(cameraGalleryServiceProvider).transferGate.savingOriginals,
      keepLocalRecipe: (recipe) => recipe is CameraFilmRecipe
          ? SyncRepository(ref.read(databaseProvider)).saveCameraRecipe(recipe)
          : ref.read(filmRepositoryProvider).saveRecipe(recipe));
  ref.listen(companionNetworkReadyProvider, (_, ready) {
    if (!ready) controller.disconnected();
  });
  ref.listen(extensionPendingPresenceProvider(identity.instanceId), (_, __) {
    if (ref.read(appForegroundProvider) &&
        ref.read(companionNetworkReadyProvider)) {
      unawaited(controller.refresh());
    }
  });
  ref.onDispose(controller.dispose);
  return controller;
});
