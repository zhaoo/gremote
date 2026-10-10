import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shoot_page_test.dart';

void main() {
  testWidgets('planned ramp locks controls, supports dimming and can stop',
      (tester) async {
    final harness = await pumpShoot(tester, connect: true);

    await tester.tap(find.byKey(const Key('mode-timelapse')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('计划渐变'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.gateways.trace, contains('keepScreenOn:true'));
    expect(find.text('☾'), findsOneWidget);
    await tester.tap(find.text('☾'));
    await tester.pump();
    expect(find.textContaining('点击恢复显示'), findsOneWidget);
    await tester.tap(find.textContaining('点击恢复显示'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('shutter-button')));
    await tester.pumpAndSettle();
    expect(harness.gateways.trace, contains('keepScreenOn:false'));
  });
}
