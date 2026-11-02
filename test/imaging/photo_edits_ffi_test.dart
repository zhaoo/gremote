import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/imaging/ffi_imaging_engine.dart';
import 'package:gremote/imaging/imaging_engine.dart';
import 'package:gremote/imaging/imaging_exception.dart';

import 'ffi_imaging_engine_test.dart' show bytesOf, cube, openReadOnly;

// Construct the documented wire format independently of the model serializer.
Float32List neutralEdits() {
  final edits = Float32List(1062)
    ..[0] = 1
    ..[12] = 0.5
    ..[13] = 0.5
    ..[15] = 0.5
    ..[16] = 0.5
    ..[18] = 0.5
    ..[19] = 0.5
    ..[21] = 0.5
    ..[22] = 0.5
    ..[25] = 0.5
    ..[29] = 7331
    ..[32] = 1
    ..[33] = 1;
  for (var channel = 0; channel < 4; channel++) {
    for (var i = 0; i < 256; i++) {
      edits[38 + channel * 256 + i] = i / 255;
    }
  }
  return edits;
}

void main() {
  final libraryPath = Platform.environment['GREMOTE_IMAGING_LIB'] ??
      'native/imaging/build/host/libgremote_imaging.dylib';
  final engine = FfiImagingEngine(libraryPath: libraryPath);
  const fixture = 'test/fixtures/gradient_60x40.jpg';
  final invalidArgument = throwsA(isA<ImagingException>()
      .having((e) => e.code, 'code', ImagingErrorCode.invalidArgument));

  setUpAll(() {
    if (!File(libraryPath).existsSync()) {
      fail('Build the host library first: scripts/build_native_host.sh');
    }
  });

  test('neutral render is identical and exposure renders a source copy',
      () async {
    final source = PreviewImage(
        width: 2,
        height: 1,
        rgba: Uint8List.fromList([64, 80, 96, 255, 96, 64, 32, 200]));
    final original = Uint8List.fromList(source.rgba);
    final neutral = await engine.renderPhoto(source,
        adjustments: neutralEdits(), width: 2, height: 1);
    expect(neutral.rgba, original);
    final brighter = await engine.renderPhoto(source,
        adjustments: neutralEdits()..[1] = 1, width: 2, height: 1);
    expect(brighter.rgba[0], greaterThan(original[0]));
    expect(brighter.rgba[3], 255);
    expect(brighter.rgba[7], 200);
    expect(source.rgba, original);
  });

  test('rotation and crop use the requested output geometry', () async {
    final source = await engine.decodePreview(
        fd: openReadOnly(fixture), orientation: 1, maxEdge: 60);
    final rendered = await engine.renderPhoto(source,
        adjustments: neutralEdits()
          ..[30] = 0.25
          ..[32] = 0.5
          ..[34] = 1,
        width: 20,
        height: 60);
    expect(rendered.width, 20);
    expect(rendered.height, 60);
    expect(rendered.rgba.length, 20 * 60 * 4);
  });

  test('LUT is applied by the unified render pipeline', () async {
    final source = PreviewImage(
        width: 1, height: 1, rgba: Uint8List.fromList([255, 0, 0, 255]));
    final swap = bytesOf(cube(17, (r, g, b) => [b, g, r]));
    final rendered = await engine.renderPhoto(source,
        adjustments: neutralEdits(), cube: swap, width: 1, height: 1);
    expect(rendered.rgba, [0, 0, 255, 255]);
    expect(source.rgba, [255, 0, 0, 255]);
  });

  test('exported JPEG decodes close to same-size rendered preview', () async {
    final dir = await Directory.systemTemp.createTemp('gremote-photo-ffi');
    addTearDown(() => dir.delete(recursive: true));
    final source = await engine.decodePreview(
        fd: openReadOnly(fixture), orientation: 1, maxEdge: 60);
    final edits = neutralEdits()
      ..[1] = 0.4
      ..[2] = 0.15
      ..[11] = 0.3
      ..[14] = 0.05
      ..[27] = 0.1
      ..[30] = 0.1
      ..[32] = 0.8;
    final preview = await engine.renderPhoto(source,
        adjustments: edits, width: 36, height: 30);
    final output = '${dir.path}/edited.jpg';
    await engine.exportJpeg(ExportJob(
      fd: openReadOnly(fixture),
      orientation: 1,
      adjustments: edits,
      photoWidth: 36,
      photoHeight: 30,
      photoX: 0,
      photoY: 0,
      canvasWidth: 36,
      canvasHeight: 30,
      background: 0xff000000,
      quality: 100,
      outputPath: output,
    ));
    final jpeg = await engine.decodePreview(
        fd: openReadOnly(output), orientation: 1, maxEdge: 36);
    expect(jpeg.width, preview.width);
    expect(jpeg.height, preview.height);
    var error = 0;
    for (var i = 0; i < jpeg.rgba.length; i++) {
      if (i % 4 != 3) error += (jpeg.rgba[i] - preview.rgba[i]).abs();
    }
    expect(error / (36 * 30 * 3), lessThan(5));
  });

  test('native failures leave later renders usable', () async {
    final source = PreviewImage(
        width: 1, height: 1, rgba: Uint8List.fromList([64, 80, 96, 255]));
    await expectLater(
        engine.renderPhoto(source,
            adjustments: neutralEdits()..[0] = 2, width: 1, height: 1),
        invalidArgument);
    await expectLater(
        engine.renderPhoto(source,
            adjustments: neutralEdits(),
            cube: bytesOf('invalid cube'),
            width: 1,
            height: 1),
        throwsA(isA<ImagingException>()
            .having((e) => e.code, 'code', ImagingErrorCode.lutParse)));
    expect(
        (await engine.renderPhoto(source,
                adjustments: neutralEdits(), width: 1, height: 1))
            .rgba,
        [64, 80, 96, 255]);
  });

  test('rejects invalid dimensions and short source before native reads',
      () async {
    for (final source in [
      PreviewImage(width: 0, height: 1, rgba: Uint8List(0)),
      PreviewImage(width: -1, height: 1, rgba: Uint8List(0)),
      PreviewImage(width: 2, height: 2, rgba: Uint8List(4)),
    ]) {
      await expectLater(
          engine.renderPhoto(source,
              adjustments: neutralEdits(), width: 1, height: 1),
          invalidArgument);
    }
    final source = PreviewImage(width: 1, height: 1, rgba: Uint8List(4));
    await expectLater(
        engine.renderPhoto(source,
            adjustments: neutralEdits(), width: 0, height: 1),
        invalidArgument);
    await expectLater(
        engine.renderPhoto(source,
            adjustments: neutralEdits(), width: 0x100000001, height: 1),
        invalidArgument);
    await expectLater(
        engine.renderPhoto(source,
            adjustments: Float32List(1), width: 1, height: 1),
        invalidArgument);
    await expectLater(
        engine.renderPhoto(source,
            adjustments: neutralEdits()..[1] = double.nan, width: 1, height: 1),
        invalidArgument);
  });
}
