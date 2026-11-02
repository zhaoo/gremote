import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:gremote/imaging/imaging_engine.dart';
import 'package:gremote/imaging/imaging_exception.dart';

class RenderPhotoCall {
  RenderPhotoCall({
    required Float32List adjustments,
    required Uint8List? cube,
    required this.strength,
    required this.width,
    required this.height,
  })  : adjustments = Float32List.fromList(adjustments),
        cube = cube == null ? null : Uint8List.fromList(cube);

  final Float32List adjustments;
  final Uint8List? cube;
  final double strength;
  final int width;
  final int height;
}

class FakeImagingEngine implements ImagingEngine {
  Future<void>? renderGate;
  Future<void>? validationGate;
  int activeRenders = 0, maxActiveRenders = 0;
  int lutSize = 33;
  ImagingErrorCode? validateError;
  ImagingErrorCode? decodeError;

  /// 1-based export call index → failure.
  final exportFailures = <int, ImagingErrorCode>{};

  /// 1-based native render call index → failure.
  final renderFailures = <int, ImagingErrorCode>{};

  /// Runs before each export completes; may cancel the token.
  void Function(ExportJob job)? onExport;

  final validated = <Uint8List>[];
  final decoded = <int>[];
  final lutCalls = <double>[];
  final renderCalls = <RenderPhotoCall>[];
  final jobs = <ExportJob>[];

  @override
  Future<int> validateLut(Uint8List cube) async {
    validated.add(cube);
    if (validationGate != null) await validationGate;
    if (validateError != null) throw ImagingException(validateError!);
    return lutSize;
  }

  @override
  Future<PreviewImage> decodePreview({
    required int fd,
    required int orientation,
    required int maxEdge,
  }) async {
    decoded.add(fd);
    if (decodeError != null) throw ImagingException(decodeError!);
    return PreviewImage(
        width: 6, height: 4, rgba: Uint8List(6 * 4 * 4)..fillRange(0, 96, 128));
  }

  @override
  Future<PreviewImage> applyLut(
      PreviewImage source, Uint8List cube, double strength) async {
    lutCalls.add(strength);
    return PreviewImage(
      width: source.width,
      height: source.height,
      rgba: Uint8List.fromList([for (final v in source.rgba) 255 - v]),
    );
  }

  @override
  Future<PreviewImage> renderPhoto(
    PreviewImage source, {
    required Float32List adjustments,
    Uint8List? cube,
    double strength = 1,
    required int width,
    required int height,
  }) async {
    activeRenders++;
    if (activeRenders > maxActiveRenders) maxActiveRenders = activeRenders;
    renderCalls.add(RenderPhotoCall(
      adjustments: adjustments,
      cube: cube,
      strength: strength,
      width: width,
      height: height,
    ));
    final failure = renderFailures[renderCalls.length];
    if (renderGate != null) await renderGate;
    activeRenders--;
    if (failure != null) throw ImagingException(failure);
    if (cube != null && cube.isNotEmpty) lutCalls.add(strength);
    final output = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final from = ((y * source.height ~/ height) * source.width +
                x * source.width ~/ width) *
            4;
        final to = (y * width + x) * 4;
        for (var channel = 0; channel < 4; channel++) {
          final value = source.rgba[from + channel];
          output[to + channel] = cube != null && cube.isNotEmpty && channel < 3
              ? (value * (1 - strength) + (255 - value) * strength)
                  .round()
                  .clamp(0, 255)
              : value;
        }
      }
    }
    return PreviewImage(width: width, height: height, rgba: output);
  }

  @override
  Future<void> exportJpeg(ExportJob job, {ImagingCancelToken? cancel}) async {
    jobs.add(job);
    onExport?.call(job);
    final file = File(job.outputPath)..writeAsBytesSync([0xFF, 0xD8]);
    if (cancel?.isCancelled ?? false) {
      throw const ImagingException(ImagingErrorCode.cancelled);
    }
    final failure = exportFailures[jobs.length];
    if (failure != null) throw ImagingException(failure);
    file.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
  }
}
