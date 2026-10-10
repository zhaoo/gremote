import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shoot_page_test.dart';

void main() {
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
    await tester.tap(find.text('positiveFilm').last);
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
