import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:gremote/camera/companion/camera_film_catalog.dart';
import 'package:gremote/camera/companion/companion_protocol.dart';
import 'package:gremote/camera/companion/three_way_merge.dart';
import 'camera_film_contract_test.dart' show cameraStateFixture;

CameraFilmCatalog oldCatalog() => CameraFilmCatalog.fromJson(jsonDecode(
    File('assets/films/camera-profiles/installed-03db1c70-catalog.json')
        .readAsStringSync()));
CameraFilmCatalog newCatalog() => CameraFilmCatalog.fromJson(
    jsonDecode(File('assets/films/camera-catalog.json').readAsStringSync()));
void main() {
  test('bundled old profile metadata matches the verified delivery receipt',
      () {
    const root = 'assets/films/camera-profiles/';
    final receipt = jsonDecode(File('${root}installed-03db1c70-provenance.json')
        .readAsStringSync()) as Map;
    expect(receipt['apkSha256'],
        '0c6eaf5ea79b87cd85b72a7aeddf717fef92491c92aaac48b6a113f7bf134092');
    for (final file in (receipt['files'] as Map).entries) {
      expect(
          sha256.convert(File('$root${file.key}').readAsBytesSync()).toString(),
          file.value);
    }
    final old = oldCatalog();
    expect(
        jsonDecode(
            File('${root}installed-03db1c70-contract.json').readAsStringSync()),
        old.contract);
    for (final entry in old.entries) {
      expect(File(entry.icon).existsSync(), true);
    }
  });
  test(
      'trusted old and current catalogs preserve exact distinct recipe identities',
      () {
    final old = oldCatalog(), current = newCatalog();
    final recipe = old.recipe(33);
    expect(recipe.catalogHash, old.hash);
    expect(recipe.rendererHash, old.rendererHash);
    expect(
        CameraFilmRecipe.fromJson(Map<String, dynamic>.from(recipe.toJson()))
            .fingerprint,
        recipe.fingerprint);
    expect(old.entries.any((f) => f.id == 326), false);
    expect(() => old.recipe(326), throwsFormatException);
    expect(() => CameraFilmRecipe.fromJson({...recipe.toJson(), 'filmId': 326}),
        throwsFormatException);
    expect(current.recipe(326).filmId, 326);
    final target = current.recipe(33).toJson();
    expect(() => current.forTarget(recipe, target), throwsFormatException);
    expect(() => old.forTarget(current.recipe(33), recipe.toJson()),
        throwsFormatException);
  });
  test(
      'old snapshot recipes retain their profile and old config rejects new film IDs',
      () {
    final old = oldCatalog();
    final raw = cameraStateFixture()
      ..['catalogHash'] = old.hash
      ..['rendererHash'] = old.rendererHash;
    final snapshot = CompanionSnapshot.fromJson(raw, contract: old.contract);
    expect(snapshot.hasUnknownFields, false);
    expect(snapshot.recipeAt(9).rendererHash, old.rendererHash);
    expect(knownCompanionConfig(snapshot.config, contract: old.contract), true);
    raw['config']['slots'][9]['filmId'] = 326;
    final invalid = CompanionSnapshot.fromJson(raw, contract: old.contract);
    expect(invalid.hasUnknownFields, true);
    expect(knownCompanionConfig(invalid.config, contract: old.contract), false);
  });
  test('only pinned pairs and contracts are camera recipe authority', () {
    final current = newCatalog(), old = oldCatalog();
    expect(resolveCameraFilmProfile(old.hash, old.rendererHash), isNotNull);
    expect(resolveCameraFilmProfile(current.hash, current.rendererHash),
        isNotNull);
    expect(resolveCameraFilmProfile(old.hash, current.rendererHash), isNull);
    final json = old.recipe(33).toJson();
    expect(() => CameraFilmRecipe.fromJson({...json, 'rendererHash': 'a' * 64}),
        throwsFormatException);
    expect(() => CameraFilmRecipe.fromJson({...json, 'catalogHash': 'b' * 64}),
        throwsFormatException);
    expect(() => old.contract['maximumFilmId'] = 999, throwsUnsupportedError);
  });
}
