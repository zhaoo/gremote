import 'dart:io';
import 'dart:typed_data';

import 'package:gremote/imaging/imaging_engine.dart';
import 'package:gremote/imaging/imaging_exception.dart';

class FakeImagingEngine implements ImagingEngine {
  int lutSize = 33;
  ImagingErrorCode? validateError;
  ImagingErrorCode? decodeError;

  /// 1-based export call index → failure.
  final exportFailures = <int, ImagingErrorCode>{};

  /// Runs before each export completes; may cancel the token.
  void Function(ExportJob job)? onExport;

  final validated = <Uint8List>[];
  final decoded = <int>[];
  final lutCalls = <double>[];
  final jobs = <ExportJob>[];

  @override
  Future<int> validateLut(Uint8List cube) async {
    validated.add(cube);
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
