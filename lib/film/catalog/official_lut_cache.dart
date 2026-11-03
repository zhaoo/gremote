import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'official_film_luts.dart';

const _maxEntries = 80;
const _maxPayloadBytes = 2 * 1024 * 1024;
const _maxTotalBytes = 64 * 1024 * 1024;
const _maxManifestBytes = 6 * 1024 * 1024;
const _approximation = '官网色彩预览近似，不含颗粒、光晕等空间效果';
final _identityPattern = RegExp(
    r'^official:([1-9][0-9]{0,9}):(default|ei120|ei64|ei250):([a-f0-9]{64})$');

void _need(bool valid) {
  if (!valid) throw const FormatException('官网手机胶卷缓存无效');
}

RegExpMatch? _identity(String id) {
  final match = _identityPattern.firstMatch(id);
  return match != null &&
          match.end == id.length &&
          int.parse(match[1]!) <= 0xffffffff
      ? match
      : null;
}

/// Metadata only. Payload paths are always derived from validated hashes.
class OfficialLutRecord {
  const OfficialLutRecord._(this.id, this.name, this.filmId, this.variant,
      this.size, this.contentHash, this.byteLength);

  factory OfficialLutRecord.fromJson(Map<String, Object?> json) {
    const keys = {
      'id',
      'name',
      'filmId',
      'variant',
      'size',
      'contentHash',
      'byteLength'
    };
    _need(json.length == keys.length && json.keys.every(keys.contains));
    final id = json['id'],
        name = json['name'],
        filmId = json['filmId'],
        variant = json['variant'],
        size = json['size'],
        hash = json['contentHash'],
        length = json['byteLength'];
    _need(id is String &&
        name is String &&
        filmId is int &&
        variant is String &&
        size is int &&
        hash is String &&
        length is int);
    final match = _identity(id as String);
    _need(match != null &&
        int.parse(match[1]!) == filmId &&
        match[2] == variant &&
        match[3] == hash);
    _need((name as String).trim().isNotEmpty &&
        name.length <= 80 &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(name));
    _need((size == 15 || size == 33) &&
        (length as int) > 0 &&
        length <= _maxPayloadBytes);
    return OfficialLutRecord._(id, name, filmId as int, variant as String,
        size as int, hash as String, length as int);
  }

  final String id, name, variant, contentHash;
  final int filmId, size, byteLength;
  String get approximationLabel => _approximation;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'filmId': filmId,
        'variant': variant,
        'size': size,
        'contentHash': contentHash,
        'byteLength': byteLength,
      };
}

/// Stages immutable content; only OfficialFilmLibrary activates the shared
/// manifest. Historical payloads remain addressable by saved edit IDs forever.
class OfficialLutCache {
  OfficialLutCache({required Future<Directory> Function() directory})
      : _directory = directory;
  final Future<Directory> Function() _directory;

  Future<List<Map<String, Object?>>> stage(List<OfficialColorLut> luts) async {
    final root = (await _directory()).path;
    return Isolate.run(() => _stage(root, luts));
  }

  /// Cheap metadata and regular-file/length checks; SHA is verified on load.
  Future<List<OfficialLutRecord>> entries() async {
    final root = (await _directory()).path;
    // Avoid starting a worker for the common first-run/no-sync case. This is
    // one metadata lookup; JSON parsing and LUT hashing stay off the UI isolate.
    if (!File(p.join(root, 'official-library.json')).existsSync()) return [];
    return Isolate.run(() => _entries(root));
  }

  /// Resolves historical IDs without consulting the active manifest.
  Future<Uint8List?> load(String id) async {
    final match = _identity(id);
    if (match == null) return null;
    final root = (await _directory()).path, hash = match[3]!;
    return Isolate.run(() => _verifiedPayload(root, hash));
  }
}

String _payloadDirectory(String root) => p.join(root, 'official-luts');
String _payloadPath(String root, String hash) =>
    p.join(_payloadDirectory(root), '$hash.cube');

Future<bool> _regularPayload(String root, String hash, {int? length}) async {
  if (await FileSystemEntity.type(_payloadDirectory(root),
          followLinks: false) !=
      FileSystemEntityType.directory) return false;
  final path = _payloadPath(root, hash);
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) return false;
  final bytes = await File(path).length();
  return bytes > 0 &&
      bytes <= _maxPayloadBytes &&
      (length == null || length == bytes);
}

Future<Uint8List?> _verifiedPayload(String root, String hash,
    {int? length}) async {
  try {
    if (!await _regularPayload(root, hash, length: length)) return null;
    final bytes = await File(_payloadPath(root, hash)).readAsBytes();
    if (bytes.isEmpty ||
        bytes.length > _maxPayloadBytes ||
        (length != null && bytes.length != length) ||
        sha256.convert(bytes).toString() != hash) return null;
    return bytes;
  } on FileSystemException {
    return null;
  }
}

List<OfficialLutRecord> _records(List<dynamic> rows) {
  _need(rows.length <= _maxEntries);
  final ids = <String>{}, pairs = <String>{};
  final records = <OfficialLutRecord>[];
  var total = 0;
  for (final row in rows) {
    _need(row is Map);
    final record = OfficialLutRecord.fromJson(Map<String, Object?>.from(row));
    _need(
        ids.add(record.id) && pairs.add('${record.filmId}:${record.variant}'));
    total += record.byteLength;
    _need(total <= _maxTotalBytes);
    records.add(record);
  }
  return records;
}

Future<List<OfficialLutRecord>> _entries(String root) async {
  try {
    final manifest = File(p.join(root, 'official-library.json'));
    if (await FileSystemEntity.type(manifest.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await manifest.length() > _maxManifestBytes) return [];
    final source = await manifest.readAsBytes();
    if (source.length > _maxManifestBytes) return [];
    final json = jsonDecode(utf8.decode(source));
    if (json is! Map || json['phoneLuts'] == null) return [];
    _need(json['phoneLuts'] is List);
    final records = _records(json['phoneLuts'] as List);
    final available = <OfficialLutRecord>[];
    for (final record in records) {
      if (await _regularPayload(root, record.contentHash,
          length: record.byteLength)) available.add(record);
    }
    return available;
  } on FileSystemException {
    return [];
  } on FormatException {
    return [];
  } on TypeError {
    return [];
  }
}

Future<List<Map<String, Object?>>> _stage(
    String root, List<OfficialColorLut> luts) async {
  _need(luts.length <= _maxEntries);
  final records = _records([
    for (final lut in luts)
      {
        'id': lut.id,
        'name': lut.name,
        'filmId': lut.filmId,
        'variant': lut.variant,
        'size': lut.size,
        'contentHash': lut.contentHash,
        'byteLength': lut.cube.length,
      }
  ]);
  for (final lut in luts) {
    _need(sha256.convert(lut.cube).toString() == lut.contentHash);
  }
  if (records.isEmpty) return [];
  final directory = Directory(_payloadDirectory(root));
  var type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    await directory.create(recursive: true);
    type = await FileSystemEntity.type(directory.path, followLinks: false);
  }
  _need(type == FileSystemEntityType.directory);
  for (var i = 0; i < records.length; i++) {
    final record = records[i],
        target = _payloadPath(root, records[i].contentHash);
    final type = await FileSystemEntity.type(target, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      _need(await _verifiedPayload(root, record.contentHash,
              length: record.byteLength) !=
          null);
      continue;
    }
    final temporary = await directory.createTemp('.staging-');
    try {
      final file = await File(p.join(temporary.path, 'payload.cube'))
          .writeAsBytes(luts[i].cube, flush: true);
      final written = await file.readAsBytes();
      _need(written.length == record.byteLength &&
          sha256.convert(written).toString() == record.contentHash);
      await file.rename(target);
      _need(await _verifiedPayload(root, record.contentHash,
              length: record.byteLength) !=
          null);
    } finally {
      await temporary.delete(recursive: true);
    }
  }
  return [for (final record in records) record.toJson()];
}
