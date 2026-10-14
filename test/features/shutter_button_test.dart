import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/features/shoot/widgets/shutter_button.dart';

void main() {
  testWidgets('disconnect discards an old pending release across reconnect',
      (tester) async {
    final firstPress = Completer<void>();
    final calls = <String>[];
    Widget shutter(bool enabled) => MaterialApp(
          home: Scaffold(
            body: ShutterButton(
              enabled: enabled,
              onPressed: () {
                calls.add('press');
                return calls.length == 1 ? firstPress.future : Future.value();
              },
              onReleased: () async => calls.add('release'),
            ),
          ),
        );
    await tester.pumpWidget(shutter(true));
    await tester.tap(find.byKey(const Key('shutter-button')));
    await tester.pump();
    expect(calls, ['press']);
    await tester.pumpWidget(shutter(false));
    await tester.pumpWidget(shutter(true));
    firstPress.complete();
    await tester.pump();
    expect(calls, ['press']);
    await tester.tap(find.byKey(const Key('shutter-button')));
    await tester.pump();
    expect(calls, ['press', 'press', 'release']);
    expect(tester.takeException(), isNull);
  });
}
