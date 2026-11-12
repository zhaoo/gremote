import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/features/film_workbench/companion_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the full GR III build resolves its exact service catalog identity',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final catalogs = await container.read(bundledCameraCatalogsProvider.future);
    final profile = catalogs.singleWhere((catalog) =>
        catalog.hash ==
        '1b1b34c3da9b80de854eae3ad9fc3e85ffee5687f0e28fead0504129ff6294e8');
    expect(profile.rendererHash,
        'bcef872c4ff5789a34b47f4c1becc31303a55b95f381c032d9b73bc7cc4c1ae7');
    expect(profile.recipe(326).filmId, 326);
    expect(profile.recipe(330).filmId, 330);
    expect(() => profile.recipe(331), throwsFormatException);
    expect(profile.entries, hasLength(60));
    for (final film in profile.entries) {
      expect((await rootBundle.load(film.icon)).lengthInBytes, greaterThan(0));
    }
  });

  test('Leica films are recipes only for the matching GR III firmware profile',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final catalogs = await container.read(bundledCameraCatalogsProvider.future);
    final leica =
        await container.read(bundledLeicaCameraCatalogProvider.future);
    final rc1 = catalogs.singleWhere((c) =>
        c.hash ==
        'acfdebf15b861f78afed4b7104e0d32ba2e9c5bb36beb513c9b8286891074e19');
    expect(rc1.rendererHash,
        '6a7f612c85cf05ebd9f293131fa3d578df62bb89e3cba23d25b059bedb29c6c1');
    expect(leica.contract['maximumFilmId'], 334);
    expect(rc1.contract, leica.contract);
    const looks = {
      331: 'Leica Chrome',
      332: 'Leica Brass',
      333: 'Leica Teal',
      334: 'Leica Classic',
    };
    for (final look in looks.entries) {
      final definition = leica.film(look.key);
      expect(definition.name, look.value);
      expect(definition.group, '影像');
      final icon = await rootBundle.load(definition.icon);
      expect(icon.lengthInBytes, greaterThan(0));
      final recipe = leica.recipe(look.key);
      expect(recipe.filmId, look.key);
      expect(recipe.catalogHash, leica.hash);
      expect(rc1.recipe(look.key).catalogHash, rc1.hash);
      expect(() => rc1.forTarget(recipe, {}), throwsFormatException);
      for (final old in catalogs.where((c) => c.hash != leica.hash)) {
        if (old.hash != rc1.hash) {
          expect(() => old.recipe(look.key), throwsFormatException);
        }
        expect(resolveCameraFilmProfile(leica.hash, old.rendererHash), isNull);
      }
    }
  });
}
