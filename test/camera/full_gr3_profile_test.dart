import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
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
}
