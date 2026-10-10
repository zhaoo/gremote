import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/features/home/widgets/manual_wifi_dialog.dart';

void main() {
  testWidgets('submitting credentials closes the dialog without stale fields',
      (tester) async {
    (String, String)? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<(String, String)>(
                      context: context,
                      builder: (_) => const ManualWifiDialog(),
                    );
                  },
                  child: const Text('打开'),
                )),
      ),
    ));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'GR_TEST');
    await tester.enterText(find.byType(TextField).last, '12345678');
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect(result, ('GR_TEST', '12345678'));
    expect(tester.takeException(), isNull);
  });
}
