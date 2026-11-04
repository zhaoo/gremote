import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/darkroom/model/photo_edits.dart';
import 'package:gremote/features/darkroom/editor/widgets/adjustment_panel.dart';
import 'package:gremote/features/darkroom/editor/widgets/curve_panel.dart';

void main() {
  testWidgets('exposure accepts precise decimal value in one transaction',
      (tester) async {
    var edits = const PhotoEdits();
    var starts = 0, ends = 0;
    await tester.pumpWidget(MaterialApp(
        theme: GRemoteTheme.light,
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, set) => AdjustmentPanel(
                    edits: edits,
                    adjustments: const [PhotoAdjustment.exposure],
                    onChanged: (v) => set(() => edits = v),
                    onStart: () => starts++,
                    onEnd: () => ends++)))));
    await tester.tap(find.byKey(const ValueKey('adjustment-value')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('precision-input')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('precision-input')), '0.35');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(edits.value(PhotoAdjustment.exposure), closeTo(.35, .0001));
    expect(starts, 1);
    expect(ends, 1);
  });
  testWidgets(
      'curve precise coordinates clamp between neighbours and reset only channel',
      (tester) async {
    var edits = const PhotoEdits();
    await tester.pumpWidget(MaterialApp(
        theme: GRemoteTheme.dark,
        home: Scaffold(
            body: SingleChildScrollView(
                child: SizedBox(
                    width: 320,
                    child: StatefulBuilder(
                        builder: (context, set) => CurvePanel(
                            edits: edits,
                            onChanged: (v) => set(() => edits = v),
                            onStart: () {},
                            onEnd: () {})))))));
    await tester.tapAt(
        tester.getRect(find.byKey(const ValueKey('curve-graph'))).center);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('curve-coordinates')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('curve-output-input')), '180');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(edits.curves[0].points[1].y, closeTo(180 / 255, .0001));
    await tester.tap(find.text('红色'));
    await tester.pump();
    await tester.tap(find.text('对比'));
    await tester.pump();
    await tester.tap(find.byTooltip('曲线选项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('还原当前通道'));
    await tester.pump();
    expect(edits.curves[1], const ToneCurve());
    expect(edits.curves[0].points, hasLength(3));
  });
}
