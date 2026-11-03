import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../imaging_engine.dart';
import '../imaging_exception.dart';
import 'gpu_editor.dart';

/// Android editor/export backend. Small legacy consumers retain their explicit
/// reference methods; edited preview and export use resident GPU sessions.
class GpuImagingEngine implements ImagingEngine, SrgbExportEngine {
  @override
  bool exportsSrgb(int processVersion) => processVersion == 2;
  GpuImagingEngine(this.gpu, this.reference);
  final GpuEditor gpu;
  final ImagingEngine reference;
  @override
  Future<int> validateLut(Uint8List cube) => reference.validateLut(cube);
  @override
  Future<PreviewImage> decodePreview(
          {required int fd, required int orientation, required int maxEdge}) =>
      reference.decodePreview(
          fd: fd, orientation: orientation, maxEdge: maxEdge);
  @override
  Future<PreviewImage> applyLut(
          PreviewImage source, Uint8List cube, double strength) =>
      reference.applyLut(source, cube, strength);
  @override
  Future<PreviewImage> renderPhoto(PreviewImage source,
          {required Float32List adjustments,
          Uint8List? cube,
          double strength = 1,
          required int width,
          required int height}) =>
      reference.renderPhoto(source,
          adjustments: adjustments,
          cube: cube,
          strength: strength,
          width: width,
          height: height);
  @override
  Future<void> exportJpeg(ExportJob job, {ImagingCancelToken? cancel}) async {
    try {
      await gpu.export(job, cancel: cancel);
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') {
        throw const ImagingException(ImagingErrorCode.cancelled);
      }
      rethrow;
    }
  }
}
