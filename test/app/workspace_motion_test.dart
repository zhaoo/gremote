import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/app/widgets/workspace_motion.dart';
import 'package:gremote/app/widgets/workspace_tabs.dart';

void main() {
  testWidgets('reduced motion removes hidden actions immediately',
      (tester) async {
    var shown = true;
    var actions = 0;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
      theme: GRemoteTheme.dark,
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return Scaffold(
              body: WorkspaceReveal(
            visible: shown,
            child:
                TextButton(onPressed: () => actions++, child: const Text('保存')),
          ));
        }),
      ),
    ));
    await tester.tap(find.text('保存'));
    update(() => shown = false);
    await tester.pump();
    expect(find.text('保存'), findsNothing);
    expect(actions, 1);
    expect(tester.takeException(), isNull);
    update(() => shown = true);
    await tester.pump();
    expect(find.text('保存').hitTestable(), findsOneWidget);
    expect(actions, 1);
  });

  testWidgets('tab feedback does not submit the selected action twice',
      (tester) async {
    var selected = 0;
    final changes = <int>[];
    await tester.pumpWidget(MaterialApp(
      theme: GRemoteTheme.dark,
      home: Scaffold(
          body: StatefulBuilder(
        builder: (context, update) => WorkspaceTabs<int>(
          items: const [(0, '相册'), (1, '相机')],
          value: selected,
          onChanged: (next) {
            changes.add(next);
            update(() => selected = next);
          },
        ),
      )),
    ));
    await tester.tap(find.text('相机'));
    await tester.pump();
    await tester.tap(find.text('相机'));
    await tester.pumpAndSettle();
    expect(changes, [1]);
    expect(tester.takeException(), isNull);
  });
}
