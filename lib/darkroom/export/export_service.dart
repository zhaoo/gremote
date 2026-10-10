import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../../imaging/imaging_engine.dart';
import '../../imaging/imaging_exception.dart';
import '../../media/local/local_media_repository.dart';
import '../../media/local/media_gateway.dart';
import '../frame/frame_layout.dart';
import '../frame/overlay_rasterizer.dart';
import '../model/edit_document.dart';

typedef CubeLoader = Future<Uint8List> Function(String lutId);

enum ExportStage {
  read('读取'),
  color('调色'),
  compose('合成'),
  encode('编码'),
  save('保存');

  const ExportStage(this.label);
  final String label;
}

class ExportFailure implements Exception {
  const ExportFailure({
    required this.stage,
    required this.fileName,
    required this.code,
    required this.reason,
  });

  final ExportStage stage;
  final String fileName;
  final String code;
  final String reason;

  String get hint => switch (code) {
        'storageFull' => '清理手机存储空间后重试',
        'permissionDenied' => '在系统设置中允许 gremote 访问照片后重试',
        'tooLarge' || 'outOfMemory' => '把导出尺寸改为 2560 或 1440 后重试',
        'lutParse' || 'lutRange' || 'lutMissing' => '换一个 LUT，或重新导入该 LUT',
        'missingExif' => '确认原图仍在相册中且未损坏',
        _ => '稍后重试；仍失败请导出诊断信息',
      };

  String get message => '$fileName · ${stage.label}失败（$code）：$reason';

  @override
  String toString() => 'ExportFailure($message)';
}

class ExportCancelled implements Exception {
  const ExportCancelled();
}

@immutable
class ExportOutcome {
  const ExportOutcome({
    required this.uri,
    required this.displayName,
    required this.width,
    required this.height,
  });

  final String uri;
  final String displayName;
  final int width;
  final int height;
}

String exportFileName(String source, DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${at.year}${two(at.month)}${two(at.day)}'
      '-${two(at.hour)}${two(at.minute)}${two(at.second)}';
  return 'gremote_${p.basenameWithoutExtension(source)}_$stamp.jpg';
}

/// One photo: layout → overlays + LUT → native render → EXIF + publish.
class ExportService {
  ExportService({
    required ImagingEngine engine,
    required MediaGateway gateway,
    required CubeLoader loadCube,
    required Future<Directory> Function() tempDir,
    OverlayRasterizer rasterizer = const OverlayRasterizer(),
    DateTime Function()? clock,
  })  : _engine = engine,
        _gateway = gateway,
        _loadCube = loadCube,
        _tempDir = tempDir,
        _rasterizer = rasterizer,
        _clock = clock ?? DateTime.now;

  final ImagingEngine _engine;
  final MediaGateway _gateway;
  final CubeLoader _loadCube;
  final Future<Directory> Function() _tempDir;
  final OverlayRasterizer _rasterizer;
  final DateTime Function() _clock;

  Future<ExportOutcome> export(
    LocalMediaItem item,
    EditDocument doc, {
    ImagingCancelToken? cancel,
  }) async {
    final name = item.displayName;
    ExportFailure fail(ExportStage stage, String code, String reason) =>
        ExportFailure(stage: stage, fileName: name, code: code, reason: reason);

    final meta = item.meta;
    if (meta == null) {
      throw fail(ExportStage.read, 'missingExif', '无法读取照片的 EXIF 尺寸与方向');
    }
    final recipe = doc.recipe;
    final (pw, ph) =
        scaledPhotoSize(meta.orientedWidth, meta.orientedHeight, recipe.size);
    final layout = computeFrameLayout(
      photoWidth: pw,
      photoHeight: ph,
      style: recipe.frame,
      ratio: recipe.ratio,
      content: FrameContent.from(meta,
          title: doc.title, location: doc.location, hidden: doc.hidden),
    );

    // Everything that can fail in Dart runs before a descriptor is opened.
    Uint8List? cube;
    if (recipe.lutId case final lutId?) {
      try {
        cube = await _loadCube(lutId);
      } catch (e) {
        throw fail(ExportStage.color, 'lutMissing', '无法读取 LUT：$e');
      }
    }
    final List<ExportOverlay> overlays;
    try {
      overlays = await _rasterizer.rasterize(layout);
    } catch (e) {
      throw fail(ExportStage.compose, 'overlay', '边框文字绘制失败：$e');
    }

    final now = _clock();
    final displayName = exportFileName(name, now);
    final tempPath = p.join((await _tempDir()).path,
        'export-${item.id}-${now.microsecondsSinceEpoch}.jpg');
    try {
      final int fd;
      try {
        fd = await _gateway.openReadFd(item.id);
      } on MediaException catch (e) {
        throw fail(ExportStage.read, e.code, e.message ?? '无法打开原图');
      }
      try {
        await _engine.exportJpeg(
          ExportJob(
            fd: fd,
            orientation: meta.orientation,
            cube: cube,
            lutStrength: recipe.strength,
            photoWidth: layout.photo.width,
            photoHeight: layout.photo.height,
            photoX: layout.photo.x,
            photoY: layout.photo.y,
            canvasWidth: layout.canvasWidth,
            canvasHeight: layout.canvasHeight,
            background: layout.background,
            overlays: overlays,
            quality: recipe.quality,
            outputPath: tempPath,
          ),
          cancel: cancel,
        );
      } on ImagingException catch (e) {
        if (e.code == ImagingErrorCode.cancelled) throw const ExportCancelled();
        throw fail(_stageOf(e.code), e.code.name, e.code.label);
      }
      if (cancel?.isCancelled ?? false) throw const ExportCancelled();
      try {
        final uri = await _gateway.publishExport(
          tempPath: tempPath,
          sourceId: item.id,
          displayName: displayName,
          keepGps: recipe.keepGps,
          width: layout.canvasWidth,
          height: layout.canvasHeight,
        );
        return ExportOutcome(
          uri: uri,
          displayName: displayName,
          width: layout.canvasWidth,
          height: layout.canvasHeight,
        );
      } on MediaException catch (e) {
        throw fail(ExportStage.save, e.code, e.message ?? '无法保存到相册');
      }
    } finally {
      final temp = File(tempPath);
      if (temp.existsSync()) temp.deleteSync();
    }
  }

  static ExportStage _stageOf(ImagingErrorCode code) => switch (code) {
        ImagingErrorCode.io ||
        ImagingErrorCode.decode ||
        ImagingErrorCode.tooLarge =>
          ExportStage.read,
        ImagingErrorCode.lutParse ||
        ImagingErrorCode.lutRange =>
          ExportStage.color,
        ImagingErrorCode.encode => ExportStage.encode,
        _ => ExportStage.compose,
      };
}
