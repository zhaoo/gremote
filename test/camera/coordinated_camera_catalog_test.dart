import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles both current and coordinated M10V camera identities', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final catalogs = await container.read(bundledCameraCatalogsProvider.future);
    final original = catalogs.first;
    final coordinated = catalogs
        .singleWhere((catalog) => catalog.hash == coordinatedCameraCatalogHash);
    expect(coordinated.rendererHash, coordinatedCameraRendererHash);
    expect(coordinated.recipe(33).resolvedParameters,
        original.recipe(33).resolvedParameters);
    expect(resolveCameraFilmProfile(original.hash, coordinated.rendererHash),
        isNull);
    expect(resolveCameraFilmProfile(coordinated.hash, original.rendererHash),
        isNull);
    expect(
        catalogs.any((catalog) => catalog.hash == installedCameraCatalogHash),
        isTrue);
  });
}
