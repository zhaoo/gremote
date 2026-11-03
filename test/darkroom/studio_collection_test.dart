import 'package:flutter_test/flutter_test.dart';
import '../support/test_darkroom.dart';

void main() {
  test(
      'favorite toggles and recent confirmation survive reload without duplicates',
      () async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    await env.store.toggleLutFavorite('a');
    await env.store.toggleLutFavorite('b');
    await env.store.toggleLutFavorite('a');
    await env.store.rememberLut('a');
    await env.store.rememberLut('b');
    await env.store.rememberLut('a');
    final (recent, favorites) = await env.store.lutCollections();
    expect(recent, ['a', 'b']);
    expect(favorites, {'b'});
  });
}
