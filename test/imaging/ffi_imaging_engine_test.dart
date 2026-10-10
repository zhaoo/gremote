import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/imaging/ffi_imaging_engine.dart';
import 'package:gremote/imaging/imaging_engine.dart';
import 'package:gremote/imaging/imaging_exception.dart';

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);

int openReadOnly(String path) {
  final open =
      DynamicLibrary.process().lookupFunction<_OpenNative, _OpenDart>('open');
  final native = path.toNativeUtf8();
  try {
    final fd = open(native, 0);
    if (fd < 0) throw StateError('cannot open $path');
    return fd;
  } finally {
    malloc.free(native);
  }
}

String cube(int size, List<double> Function(double r, double g, double b) f) {
  final buffer = StringBuffer('LUT_3D_SIZE $size\n');
  for (var b = 0; b < size; b++) {
    for (var g = 0; g < size; g++) {
      for (var r = 0; r < size; r++) {
        final out = f(r / (size - 1), g / (size - 1), b / (size - 1));
        buffer.writeln(out.map((v) => v.toStringAsFixed(6)).join(' '));
      }
    }
  }
  return buffer.toString();
}

Uint8List bytesOf(String text) => Uint8List.fromList(text.codeUnits);

void main() {
  final libraryPath = Platform.environment['GREMOTE_IMAGING_LIB'] ??
      'native/imaging/build/host/libgremote_imaging.dylib';
  final engine = FfiImagingEngine(libraryPath: libraryPath);
  const fixture = 'test/fixtures/gradient_60x40.jpg';
  final swap = bytesOf(cube(17, (r, g, b) => [b, g, r]));

  setUpAll(() {
    if (!File(libraryPath).existsSync()) {
      fail('Build the host library first: scripts/build_native_host.sh');
    }
  });

  test('validates supported cubes and reports parse errors', () async {
    expect(await engine.validateLut(swap), 17);
    expect(await engine.validateLut(bytesOf(cube(32, (r, g, b) => [r, g, b]))),
        32);
    expect(await engine.validateLut(bytesOf(cube(25, (r, g, b) => [r, g, b]))),
        25);
    await expectLater(
      engine.validateLut(bytesOf('LUT_3D_SIZE 129\n')),
      throwsA(isA<ImagingException>()
          .having((e) => e.code, 'code', ImagingErrorCode.lutParse)),
    );
  });

  test('decodes an oriented preview bounded by the long edge', () async {
    final preview = await engine.decodePreview(
        fd: openReadOnly(fixture), orientation: 6, maxEdge: 30);
    expect(preview.width, 20);
    expect(preview.height, 30);
    expect(preview.rgba.length, 20 * 30 * 4);
  });

  test('applies a LUT to a preview copy', () async {
    final preview = PreviewImage(
        width: 1, height: 1, rgba: Uint8List.fromList([255, 0, 0, 255]));
    final mapped = await engine.applyLut(preview, swap, 1);
    expect(mapped.rgba, [0, 0, 255, 255]);
    expect(preview.rgba, [255, 0, 0, 255]);
    final swap25 = bytesOf(cube(25, (r, g, b) => [b, g, r]));
    expect((await engine.applyLut(preview, swap25, 1)).rgba, [0, 0, 255, 255]);
  });

  test('exports a canvas sized JPEG with overlays', () async {
    final dir = await Directory.systemTemp.createTemp('gremote-ffi');
    final output = '${dir.path}/out.jpg';
    final strip = Uint8List(70 * 6 * 4);
    for (var i = 3; i < strip.length; i += 4) {
      strip[i] = 255;
    }
    await engine.exportJpeg(ExportJob(
      fd: openReadOnly(fixture),
      orientation: 1,
      cube: swap,
      lutStrength: 1,
      photoWidth: 60,
      photoHeight: 40,
      photoX: 5,
      photoY: 5,
      canvasWidth: 70,
      canvasHeight: 60,
      background: 0xFFFFFFFF,
      overlays: [ExportOverlay(x: 0, y: 50, width: 70, height: 6, rgba: strip)],
      quality: 90,
      outputPath: output,
    ));
    final bytes = File(output).readAsBytesSync();
    expect(bytes.sublist(0, 2), [0xFF, 0xD8]);
    final decoded = await engine.decodePreview(
        fd: openReadOnly(output), orientation: 1, maxEdge: 70);
    expect(decoded.width, 70);
    expect(decoded.height, 60);
    await dir.delete(recursive: true);
  });

  test('export cancellation surfaces as cancelled', () async {
    final dir = await Directory.systemTemp.createTemp('gremote-ffi');
    final token = ImagingCancelToken()..cancel();
    await expectLater(
      engine.exportJpeg(
        ExportJob(
          fd: openReadOnly(fixture),
          orientation: 1,
          photoWidth: 60,
          photoHeight: 40,
          photoX: 0,
          photoY: 0,
          canvasWidth: 60,
          canvasHeight: 40,
          background: 0xFF000000,
          quality: 90,
          outputPath: '${dir.path}/cancel.jpg',
        ),
        cancel: token,
      ),
      throwsA(isA<ImagingException>()
          .having((e) => e.code, 'code', ImagingErrorCode.cancelled)),
    );
    expect(File('${dir.path}/cancel.jpg').existsSync(), isFalse);
    await dir.delete(recursive: true);
  });
}
