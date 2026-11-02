import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/darkroom/model/photo_edits.dart';
import 'package:gremote/features/darkroom/editor/widgets/adjustment_panel.dart';
import 'package:gremote/features/darkroom/editor/widgets/curve_panel.dart';
import 'package:gremote/features/darkroom/editor/widgets/crop_panel.dart';

Widget host(Widget child, {double scale = 1}) => MaterialApp(
    home: Scaffold(
        body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(
                child: SizedBox(width: 320, child: child)))));
void main() {
  testWidgets(
      'adjustment selection changes native range and double tap restores default',
      (tester) async {
    var edits = const PhotoEdits().withValue(PhotoAdjustment.exposure, 2);
    var starts = 0, ends = 0;
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => AdjustmentPanel(
            edits: edits,
            adjustments: const [
              PhotoAdjustment.exposure,
              PhotoAdjustment.grainSize
            ],
            onChanged: (v) => setState(() => edits = v),
            onStart: () => starts++,
            onEnd: () => ends++))));
    expect(tester.widget<Slider>(find.byType(Slider)).min, -3);
    await tester.tap(find.text('大小'));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).min, 0);
    await tester.tap(find.text('曝光'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('adjustment-value')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(const ValueKey('adjustment-value')));
    await tester.pump();
    expect(edits.value(PhotoAdjustment.exposure), 0);
    expect(starts, 1);
    expect(ends, 1);
    await tester.pump(const Duration(milliseconds: 300));
  });
  testWidgets('curve adds then drags a point and keeps endpoint x fixed',
      (tester) async {
    var edits = const PhotoEdits();
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => CurvePanel(
            edits: edits,
            onChanged: (v) => setState(() => edits = v),
            onStart: () {},
            onEnd: () {}))));
    final graph = find.byKey(const ValueKey('curve-graph'));
    final box = tester.getRect(graph);
    await tester.tapAt(box.center);
    await tester.pump();
    expect(edits.curves.first.points, hasLength(3));
    await tester.dragFrom(box.center, const Offset(30, -35));
    await tester.pump();
    expect(edits.curves.first.points[1].x, greaterThan(.5));
    expect(edits.curves.first.points[1].y, greaterThan(.5));
    await tester.dragFrom(
        box.bottomLeft + const Offset(16, -16), const Offset(30, -30));
    await tester.pump();
    expect(edits.curves.first.points.first.x, 0);
    await tester.tapAt(box.center + const Offset(30, -35));
    await tester.pump();
    await tester.tap(find.text('删除控制点'));
    await tester.pump();
    expect(edits.curves.first.points, hasLength(2));
    await tester.tap(find.text('R'));
    await tester.pump();
    await tester.tap(find.text('对比'));
    await tester.pump();
    expect(edits.curves[1].points, hasLength(4));
    expect(edits.curves.first.points, hasLength(2));
  });
  testWidgets(
      'crop ratios use rotated dimensions and rotation resets rectangle',
      (tester) async {
    var crop = const CropEdit();
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => CropPanel(
            crop: crop,
            sourceWidth: 400,
            sourceHeight: 300,
            onChanged: (v) => setState(() => crop = v),
            onStart: () {},
            onEnd: () {}))));
    await tester.tap(find.text('1:1'));
    await tester.pump();
    expect(crop.width, closeTo(.75, .001));
    expect(crop.height, 1);
    expect(crop.aspectRatio, 1);
    await tester.tap(find.byTooltip('向右旋转90°'));
    await tester.pump();
    expect(crop.quarterTurns, 1);
    expect(crop.aspectRatio, 0);
    expect(crop.width, 1);
    expect(crop.height, 1);
    await tester.tap(find.text('4:3'));
    await tester.pump();
    expect(crop.height, closeTo(.5625, .001));
  });
  testWidgets(
      'crop selection moves and resizes inside image and balances gesture history',
      (tester) async {
    var crop = const CropEdit(left: .2, top: .2, width: .5, height: .5);
    var starts = 0, ends = 0;
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => SizedBox(
            height: 240,
            child: CropSelection(
                crop: crop,
                onChanged: (v) => setState(() => crop = v),
                onStart: () => starts++,
                onEnd: () => ends++,
                child: const ColoredBox(color: Colors.grey))))));
    await tester.drag(
        find.byKey(const ValueKey('crop-move')), const Offset(400, 400));
    await tester.pump();
    expect(crop.left, closeTo(.5, .001));
    expect(crop.top, closeTo(.5, .001));
    await tester.drag(
        find.byKey(const ValueKey('crop-handle-0')), const Offset(-400, -400));
    await tester.pump();
    expect(crop.left, 0);
    expect(crop.top, 0);
    expect(crop.width, 1);
    expect(crop.height, 1);
    expect(starts, 2);
    expect(ends, 2);
  });
  testWidgets(
      'locked crop ratio survives corner drag, boundaries and cancellation',
      (tester) async {
    var crop = const CropEdit(
        left: .1, top: .1, width: .6, height: .8, aspectRatio: 1);
    var starts = 0, ends = 0;
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => SizedBox(
            height: 240,
            child: CropSelection(
                crop: crop,
                onChanged: (v) => setState(() => crop = v),
                onStart: () => starts++,
                onEnd: () => ends++,
                child: const ColoredBox(color: Colors.grey))))));
    await tester.drag(
        find.byKey(const ValueKey('crop-handle-2')), const Offset(400, 300));
    await tester.pump();
    expect(crop.width / crop.height, closeTo(.75, .001));
    expect(crop.left + crop.width, lessThanOrEqualTo(1));
    expect(crop.top + crop.height, lessThanOrEqualTo(1));
    expect(crop.aspectRatio, 1);
    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('crop-handle-0'))));
    await gesture.moveBy(const Offset(300, 300));
    await gesture.cancel();
    await tester.pump();
    expect(crop.width / crop.height, closeTo(.75, .001));
    expect(crop.width * 320, greaterThanOrEqualTo(24));
    expect(starts, 2);
    expect(ends, 2);
  });
  testWidgets('all panels fit narrow width with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final panel in [
      AdjustmentPanel(
          edits: const PhotoEdits(),
          adjustments: PhotoAdjustment.values,
          onChanged: (_) {},
          onStart: () {},
          onEnd: () {}),
      CurvePanel(
          edits: const PhotoEdits(),
          onChanged: (_) {},
          onStart: () {},
          onEnd: () {}),
      CropPanel(
          crop: const CropEdit(),
          sourceWidth: 400,
          sourceHeight: 300,
          onChanged: (_) {},
          onStart: () {},
          onEnd: () {})
    ]) {
      await tester.pumpWidget(host(panel, scale: 2));
      expect(tester.takeException(), isNull);
    }
  });
}
