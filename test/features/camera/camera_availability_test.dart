import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/camera/companion/companion_protocol.dart';
import 'package:gremote/camera/companion/sync_state.dart';
import 'package:gremote/features/camera/camera_availability.dart';
import '../../camera/camera_film_contract_test.dart'
    show cameraCapabilitiesFixture, cameraStateFixture;

CompanionSyncState readyState({bool upload = false, bool write = true}) {
  final caps = cameraCapabilitiesFixture();
  caps['capabilities']['uploadFilm'] = upload;
  caps['capabilities']['writeState'] = write;
  return CompanionSyncState(
    connectionStatus: SyncConnectionStatus.ready,
    capabilities:
        CompanionCapabilities.fromJson(caps, contract: cameraContract),
    snapshot: CompanionSnapshot.fromJson(cameraStateFixture(),
        contract: cameraContract),
    stale: false,
    readOnly: false,
  );
}

void main() {
  test('cached ready capabilities cannot unlock a disconnected camera', () {
    final availability = CameraAvailability.fromState(
        connected: false, paired: true, sync: readyState());
    expect(availability.canReadFilms, isFalse);
    expect(availability.canInstallFilms, isFalse);
  });
  test('missing pairing or failed detection remains unconfirmed', () {
    for (final paired in [false, true]) {
      final availability = CameraAvailability.fromState(
          connected: true,
          paired: paired,
          sync: const CompanionSyncState(
              connectionStatus: SyncConnectionStatus.error));
      expect(availability.canInstallFilms, isFalse);
      expect(availability.hint, isNot(contains('未安装')));
    }
  });
  test('stale or pending configuration cannot unlock installation', () {
    for (final state in [
      readyState().copyWith(stale: true),
      readyState().copyWith(operationStatus: SyncOperationStatus.unknown),
      readyState().copyWith(readOnly: true),
    ]) {
      expect(
          CameraAvailability.fromState(
                  connected: true, paired: true, sync: state)
              .canInstallFilms,
          isFalse);
    }
  });
  test('read only firmware keeps slots readable without installation', () {
    final availability = CameraAvailability.fromState(
        connected: true, paired: true, sync: readyState(write: false));
    expect(availability.canReadFilms, isTrue);
    expect(availability.canInstallFilms, isFalse);
  });
  test('fresh authenticated capability unlocks supported installation', () {
    final availability = CameraAvailability.fromState(
        connected: true, paired: true, sync: readyState());
    expect(availability.canReadFilms, isTrue);
    expect(availability.canInstallFilms, isTrue);
  });
  test('a different pairing identity cannot reuse cached capabilities', () {
    final availability = CameraAvailability.fromState(
        connected: true,
        paired: true,
        sync: readyState(),
        expectedInstanceId: 'ff' * 16);
    expect(availability.canReadFilms, isFalse);
    expect(availability.canInstallFilms, isFalse);
  });
}
