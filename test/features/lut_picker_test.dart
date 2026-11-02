import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/app/theme/app_theme.dart';
import 'package:gremote/darkroom/darkroom_providers.dart';
import 'package:gremote/darkroom/lut/lut_library.dart';
import 'package:gremote/darkroom/model/photo_edits.dart';
import 'package:gremote/features/darkroom/editor/widgets/frame_preview.dart';
import 'package:gremote/features/darkroom/editor/widgets/lut_picker.dart';
import 'package:gremote/imaging/imaging_engine.dart';

import '../support/fake_imaging_engine.dart';
import '../support/test_darkroom.dart';

const entries = [
  LutEntry(id: 'one', name: '清透', size: 17, imported: false),
  LutEntry(id: 'two', name: '暖调', size: 17, imported: false),
  LutEntry(id: 'three', name: '胶片', size: 17, imported: true),
];

class ControlledEngine extends FakeImagingEngine {
  final pending = <Completer<void>>[];
  final sources = <PreviewImage>[];
  int active = 0;
  int maxActive = 0;

  @override
  Future<PreviewImage> renderPhoto(PreviewImage source,
      {required Float32List adjustments,
      Uint8List? cube,
      double strength = 1,
      required int width,
      required int height}) async {
    sources.add(source);
    renderCalls.add(RenderPhotoCall(
        adjustments: adjustments,
        cube: cube,
        strength: strength,
        width: width,
        height: height));
    active++;
    if (active > maxActive) maxActive = active;
    final wait = Completer<void>();
    pending.add(wait);
    await wait.future;
    active--;
    return PreviewImage(
        width: width,
        height: height,
        rgba: Uint8List(width * height * 4)
          ..fillRange(0, width * height * 4, source.rgba[0]));
  }
}

class TestLibrary extends LutLibrary {
  TestLibrary(TestDarkroom env, ImagingEngine engine)
      : super(store: env.store, engine: engine, dataDir: () async => env.dir);

  @override
  Future<Uint8List> load(String id) async =>
      Uint8List.fromList([id.codeUnitAt(0)]);
}

Widget picker(
        {PreviewImage? source,
        PhotoEdits edits = const PhotoEdits(),
        ValueChanged<String?>? select,
        ValueChanged<double>? strength,
        VoidCallback? start,
        VoidCallback? end,
        VoidCallback? import,
        List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
          theme: GRemoteTheme.dark,
          home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: LutPicker(
                  source: source,
                  edits: edits,
                  entries: entries,
                  selected: 'one',
                  strength: .7,
                  onSelected: select ?? (_) {},
                  onStrength: strength ?? (_) {},
                  onStart: start ?? () {},
                  onEnd: end ?? () {},
                  onImport: import ?? () {},
                )),
          )),
    );

void main() {
  testWidgets(
      'selection, original, import and continuous strength work at 320px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
    final selected = <String?>[];
    final strengths = <double>[];
    var starts = 0, ends = 0, imports = 0;
    await tester.pumpWidget(picker(
        select: selected.add,
        strength: strengths.add,
        start: () => starts++,
        end: () => ends++,
        import: () => imports++));
    await tester.tap(find.text('清透'));
    await tester.tap(find.text('原图'));
    await tester.tap(find.byTooltip('导入 LUT'));
    await tester.drag(find.byType(Slider), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(selected, ['one', null]);
    expect(imports, 1);
    expect(strengths, isNotEmpty);
    expect(starts, 1);
    expect(ends, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thumbnail rendering is serial, crop sized and stale safe',
      (tester) async {
    final env = await TestDarkroom.create();
    addTearDown(env.close);
    final engine = ControlledEngine();
    final overrides = [
      imagingEngineProvider.overrideWithValue(engine),
      lutLibraryProvider.overrideWithValue(TestLibrary(env, engine)),
    ];
    final oldSource = PreviewImage(
        width: 200,
        height: 100,
        rgba: Uint8List(200 * 100 * 4)..fillRange(0, 200 * 100 * 4, 10));
    final newSource = PreviewImage(
        width: 100,
        height: 200,
        rgba: Uint8List(100 * 200 * 4)..fillRange(0, 100 * 200 * 4, 90));
    final edits = const PhotoEdits()
        .copyWith(crop: const CropEdit(width: .5, quarterTurns: 1));
    await tester.pumpWidget(
        picker(source: oldSource, edits: edits, overrides: overrides));
    await tester.pump();
    expect(engine.renderCalls, hasLength(1));
    expect((engine.renderCalls.first.width, engine.renderCalls.first.height),
        (24, 96));
    expect(engine.renderCalls.first.adjustments, edits.nativeParameters);
    expect(engine.renderCalls.first.cube, isNull);
    expect(engine.renderCalls.first.strength, .7);
    await tester.pumpWidget(
        picker(source: newSource, edits: edits, overrides: overrides));
    await tester.pump();
    expect(engine.renderCalls, hasLength(1), reason: 'old job stays in flight');
    engine.pending.first.complete();
    await tester.pump();
    await tester.pump();
    expect(engine.maxActive, 1);
    expect(engine.sources.last, same(newSource));
    expect((engine.renderCalls.last.width, engine.renderCalls.last.height),
        (96, 96));
    expect(
        tester
            .widgetList<FramePreview>(find.byType(FramePreview))
            .where((widget) => widget.image != null),
        isEmpty,
        reason: 'old thumbnail never enters the new photo strip');
    engine.pending.last.complete();
    await tester.pump();
    await tester.pump();
    expect(
        tester
            .widgetList<FramePreview>(find.byType(FramePreview))
            .where((widget) => widget.image != null)
            .every((widget) => widget.image!.rgba[0] == 90),
        isTrue);
    expect(engine.renderCalls.last.cube, [111],
        reason: 'the next tile loads its actual LUT through the library');
    expect(
        tester.widgetList<FramePreview>(find.byType(FramePreview)), isNotEmpty);
    await tester.pumpWidget(
        picker(source: oldSource, edits: edits, overrides: overrides));
    await tester.pump();
    expect(tester.widgetList<FramePreview>(find.byType(FramePreview)), isEmpty,
        reason: 'completed thumbnails also clear when the photo changes');
    final callsBeforeDispose = engine.renderCalls.length;
    await tester.pumpWidget(const SizedBox());
    for (final task in engine.pending) {
      if (!task.isCompleted) task.complete();
    }
    await tester.pump();
    expect(engine.renderCalls.length, callsBeforeDispose);
    expect(tester.takeException(), isNull);
  });
}
