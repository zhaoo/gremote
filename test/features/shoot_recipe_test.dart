import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/recipe/recipe_store.dart';

import 'shoot_page_test.dart';

void main() {
  testWidgets('professional ISO and three recipe shots persist capture tags',
      (tester) async {
    final harness = await pumpShoot(tester, connect: true);
    await tester.tap(find.byKey(const Key('mode-pro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('param-sv')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('400').last);
    await tester.pumpAndSettle();
    expect(harness.gateways.camera.props['sv'], '400');

    await tester.tap(find.byKey(const Key('recipe-toggle')));
    await tester.pumpAndSettle();
    for (final (name, effect) in [
      ('正片', 'positiveFilm'),
      ('负片', 'negativeFilm'),
      ('黑白', 'monotone'),
    ]) {
      await tester.tap(find.text('＋ 新建'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('recipe-name')), name);
      await tester.tap(find.byKey(const Key('recipe-effect')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find
          .text({
            'positiveFilm': '正片',
            'negativeFilm': '负片',
            'monotone': '黑白'
          }[effect]!)
          .last);
      await tester.tap(find
          .text({
            'positiveFilm': '正片',
            'negativeFilm': '负片',
            'monotone': '黑白'
          }[effect]!)
          .last);
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const Key('mode-bracket')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('配方包围').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();

    expect(harness.gateways.camera.files, hasLength(3));
    final tags = await harness.env.db.query('capture_tags', orderBy: 'id ASC');
    expect(tags.map((tag) => tag['effect']),
        ['positiveFilm', 'negativeFilm', 'monotone']);
    final recipes = await RecipeStore(harness.env.db).recipes();
    expect(tags.map((tag) => tag['combo_recipe_id']),
        recipes.map((recipe) => recipe.id));
    expect(harness.gateways.camera.props['effect'], 'standard');
    expect(harness.gateways.camera.props['sv'], '400');
  });

  testWidgets('creates, activates and detects detachment of a combo recipe',
      (tester) async {
    final harness = await pumpShoot(tester, connect: true);

    await tester.tap(find.byKey(const Key('recipe-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('原厂'), findsOneWidget);
    await tester.tap(find.text('＋ 新建'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('recipe-name')), '街头正片');
    await tester.tap(find.byKey(const Key('recipe-effect')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('正片').last);
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('街头正片'), findsOneWidget);
    await tester.tap(find.text('街头正片'));
    await tester.pumpAndSettle();
    expect(harness.gateways.camera.props['effect'], 'positiveFilm');

    harness.gateways.camera.bodyChange('effect', 'standard');
    await tester.pumpAndSettle();
    expect(find.text('已脱离'), findsOneWidget);
  });
}
