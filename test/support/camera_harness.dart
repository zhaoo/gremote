import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/connection/connection_controller.dart';
import 'package:gremote/camera/gateway/fake_camera_model.dart';
import 'package:gremote/camera/gateway/fake_gateways.dart';
import 'package:gremote/camera/sync/camera_state.dart';
import 'package:gremote/camera/sync/camera_state_controller.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/diagnostics/diagnostic_store.dart';
import 'package:gremote/platform/camera_permission_gate.dart';
import 'package:gremote/storage/gremote_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class NoopDiagnosticPersistence implements DiagnosticPersistence {
  @override
  Future<void> write(String json) async {}
}

/// A ProviderContainer wired to the fake camera and an in-memory database.
class CameraHarness {
  CameraHarness._(this.container, this.gateways, this.db, this.diagnostics);

  static Future<CameraHarness> create({
    FakeCameraModel? camera,
    List<Override> overrides = const [],
  }) async {
    sqfliteFfiInit();
    final db = await GRemoteDatabase.open(
        factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    final gateways =
        FakeCameraGateways(stepDelay: Duration.zero, camera: camera);
    final diagnostics =
        DiagnosticStore(persistence: NoopDiagnosticPersistence());
    final container = ProviderContainer(overrides: [
      cameraGatewaysProvider.overrideWithValue(gateways),
      cameraPermissionGateProvider.overrideWithValue(
          CameraPermissionGate(const GrantedCameraPermissionAdapter())),
      databaseProvider.overrideWithValue(db),
      diagnosticStoreProvider.overrideWithValue(diagnostics),
      ...overrides,
    ]);
    return CameraHarness._(container, gateways, db, diagnostics);
  }

  final ProviderContainer container;
  final FakeCameraGateways gateways;
  final Database db;
  final DiagnosticStore diagnostics;

  FakeCameraModel get camera => gateways.camera;
  CameraState get state => container.read(cameraStateControllerProvider);
  CameraStateController get controller =>
      container.read(cameraStateControllerProvider.notifier);

  /// Connects and waits for the first props readback.
  Future<void> connect() async {
    container.read(cameraStateControllerProvider);
    await container.read(connectionControllerProvider.notifier).connect();
    for (var i = 0; i < 50 && state.params.isEmpty; i++) {
      await pumpEventQueue();
    }
    await pumpEventQueue();
  }

  Future<void> dispose() async {
    container.dispose();
    await pumpEventQueue();
    gateways.dispose();
    await db.close();
  }
}
