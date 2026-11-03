import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../../imaging/imaging_engine.dart';
import '../../imaging/imaging_exception.dart';
import '../../film/catalog/official_lut_cache.dart';
import '../store/darkroom_store.dart';
import 'builtin_looks.dart';

const maxCubeBytes = 16 * 1024 * 1024;

@immutable
class LutEntry {
  const LutEntry({
    required this.id,
    required this.name,
    required this.size,
    required this.imported,
    this.official = false,
    this.filmId,
    this.description = '',
  });

  final String id;
  final String name;
  final int size;
  final bool imported;
  final bool official;
  final int? filmId;
  final String description;
}

class LutImportException implements Exception {
  const LutImportException(this.reason);

  final String reason;

  @override
  String toString() => 'LutImportException($reason)';
}

/// Builtin looks from assets plus user-imported `.cube` files.
class LutLibrary {
  LutLibrary({
    required DarkroomStore store,
    required ImagingEngine engine,
    required Future<Directory> Function() dataDir,
    AssetBundle? bundle,
    OfficialLutCache? officialCache,
  })  : _store = store,
        _engine = engine,
        _dataDir = dataDir,
        _officialCache = officialCache ?? OfficialLutCache(directory: dataDir),
        _bundle = bundle ?? rootBundle;

  final DarkroomStore _store;
  final ImagingEngine _engine;
  final Future<Directory> Function() _dataDir;
  final AssetBundle _bundle;
  final OfficialLutCache _officialCache;

  Future<List<LutEntry>> entries() async => [
        for (final look in builtinLooks)
          LutEntry(
            id: look.id,
            name: look.name,
            size: 33,
            imported: false,
            description: look.description,
          ),
        for (final lut in await _store.importedLuts())
          LutEntry(id: lut.id, name: lut.name, size: lut.size, imported: true),
        for (final lut in await _officialCache.entries())
          LutEntry(
              id: lut.id,
              name: lut.variant == 'default'
                  ? lut.name
                  : '${lut.name} · ${lut.variant.toUpperCase()}',
              size: lut.size,
              imported: false,
              official: true,
              filmId: lut.filmId,
              description: lut.approximationLabel),
      ];

  Future<Uint8List> load(String id) async {
    if (id.startsWith('official:')) {
      final bytes = await _officialCache.load(id);
      if (bytes == null) throw LutImportException('官网胶卷色彩缓存不可用：$id');
      return bytes;
    }
    for (final look in builtinLooks) {
      if (look.id == id) {
        final data = await _bundle.load(look.assetPath);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }
    }
    final lut = await _imported(id);
    if (lut == null) throw LutImportException('LUT 不存在：$id');
    return File(lut.filePath).readAsBytes();
  }

  Future<LutEntry> import(String fileName, Uint8List bytes) async {
    if (bytes.length > maxCubeBytes) {
      throw const LutImportException('文件过大（上限 16 MiB）');
    }
    final int size;
    try {
      size = await _engine.validateLut(bytes);
    } on ImagingException catch (e) {
      throw LutImportException(describeCubeProblem(bytes, e.code));
    }
    final sha = sha256.convert(bytes).toString();
    final dir = Directory(p.join((await _dataDir()).path, 'luts'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '$sha.cube'));
    if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
    final stem = p.basenameWithoutExtension(fileName).trim();
    final lut = await _store.addImportedLut(
      name: stem.isEmpty ? '导入 LUT' : stem,
      size: size,
      sha256: sha,
      filePath: file.path,
    );
    return LutEntry(id: lut.id, name: lut.name, size: lut.size, imported: true);
  }

  Future<void> delete(String id) async {
    final lut = await _imported(id);
    if (lut == null) return;
    await _store.deleteLut(id);
    final file = File(lut.filePath);
    if (file.existsSync()) file.deleteSync();
  }

  Future<ImportedLut?> _imported(String id) async {
    for (final lut in await _store.importedLuts()) {
      if (lut.id == id) return lut;
    }
    return null;
  }
}

/// Turns the native verdict into a specific, user-facing reason.
String describeCubeProblem(Uint8List bytes, ImagingErrorCode code) {
  switch (code) {
    case ImagingErrorCode.lutRange:
      return '数值超出 DOMAIN 范围';
    case ImagingErrorCode.tooLarge:
      return '文件过大（上限 16 MiB）';
    case ImagingErrorCode.lutParse:
      break;
    default:
      return code.label;
  }
  final lines = String.fromCharCodes(bytes).split(RegExp(r'\r?\n'));
  int? size;
  var rows = 0;
  for (final raw in lines) {
    final line = raw.trim();
    final match = RegExp(r'^LUT_3D_SIZE\s+(\d+)').firstMatch(line);
    if (match != null) size = int.parse(match.group(1)!);
    if (RegExp(r'^[-+.\d]').hasMatch(line)) rows++;
  }
  if (size == null) return '缺少 LUT_3D_SIZE（只支持 3D LUT）';
  if (size < 2 || size > 128) {
    return '尺寸 $size 不支持（支持 2–128 点）';
  }
  final expected = size * size * size;
  if (rows != expected) return '数据行数不符（应为 $expected 行，实际 $rows 行）';
  return '含非数字、NaN 或无法解析的行';
}
