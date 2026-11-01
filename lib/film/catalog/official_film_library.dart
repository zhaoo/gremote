import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const officialFilmOrigin = 'https://m10v.izhaoo.com';

class OfficialFilm {
  const OfficialFilm(
      {required this.id,
      required this.name,
      required this.group,
      required this.icon,
      this.description = ''});
  final int id;
  final String name, group, icon, description;
  factory OfficialFilm.parse(Map<String, dynamic> json) {
    final id = json['id'],
        name = json['name'],
        group = json['group'],
        icon = json['icon_url'];
    if (id is! int ||
        id < 1 ||
        id > 321 ||
        name is! String ||
        name.isEmpty ||
        name.length > 80 ||
        group is! String ||
        group.length > 80 ||
        icon is! String) {
      throw const FormatException('官网胶卷目录格式无效');
    }
    final uri = Uri.parse(officialFilmOrigin).resolve(icon);
    if (uri.origin != officialFilmOrigin || !uri.path.startsWith('/gr3/')) {
      throw const FormatException('胶卷图片地址无效');
    }
    final description = json['description'];
    return OfficialFilm(
        id: id,
        name: name,
        group: group,
        icon: uri.toString(),
        description: description is String ? description : '');
  }
}

List<OfficialFilm> parseOfficialCatalog(String source) {
  final json = jsonDecode(source);
  if (json is! Map || json['films'] is! List) {
    throw const FormatException('官网胶卷目录格式无效');
  }
  final films = (json['films'] as List)
      .map((f) => OfficialFilm.parse(Map<String, dynamic>.from(f as Map)))
      .toList();
  if (films.isEmpty ||
      films.length > 256 ||
      films.length != json['film_count'] ||
      films.map((f) => f.id).toSet().length != films.length) {
    throw const FormatException('官网胶卷目录数量无效');
  }
  return films;
}

int filmCrc(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var b = 0; b < 8; b++) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (~crc) & 0xffffffff;
}

void validateOfficialPack(List<int> input, Set<int> expectedIds,
    {String? expectedRenderer}) {
  void need(bool value) {
    if (!value) throw const FormatException('官网胶卷库校验失败');
  }

  need(input.length >= 4096 && input.length <= 4096 + 256 * 12288);
  final bytes = Uint8List.fromList(input), data = ByteData.sublistView(bytes);
  need(ascii.decode(bytes.sublist(0, 8), allowInvalid: true) == 'M10VSD1\x00' &&
      data.getUint32(8, Endian.little) == 1);
  final count = data.getUint32(16, Endian.little);
  need(count > 0 &&
      count <= 256 &&
      count == expectedIds.length &&
      bytes.length == 4096 + count * 12288 &&
      data.getUint32(12, Endian.little) == bytes.length &&
      data.getUint32(20, Endian.little) == 12288 &&
      data.getUint32(24, Endian.little) == 239 &&
      data.getUint32(28, Endian.little) == 1);
  need(filmCrc(bytes.sublist(0, 4092)) == data.getUint32(4092, Endian.little));
  final ids = <int>{};
  for (var i = 0; i < count; i++) {
    final id = data.getUint32(64 + 12 * i, Endian.little);
    need(ids.add(id) &&
        expectedIds.contains(id) &&
        data.getUint32(72 + 12 * i, Endian.little) == 1);
    final record = Uint8List.sublistView(
            bytes, 4096 + i * 12288, 4096 + (i + 1) * 12288),
        r = ByteData.sublistView(record);
    need(ascii.decode(record.sublist(0, 8), allowInvalid: true) == 'M10VREC1' &&
        r.getUint32(8, Endian.little) == id);
    final crc = r.getUint32(12284, Endian.little);
    need(filmCrc(record.sublist(0, 12284)) == crc &&
        crc == data.getUint32(68 + 12 * i, Endian.little));
    final renderer = record
        .sublist(8448, 8480)
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    need(record.sublist(8448, 8480).any((v) => v != 0) &&
        (expectedRenderer == null || renderer == expectedRenderer));
  }
}

/// Reads the website's stored-entry ZIP in memory. Never extracts paths to disk.
Uint8List officialPackFromZip(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  var offset = 0;
  Uint8List? pack;
  while (offset + 30 <= zip.length &&
      data.getUint32(offset, Endian.little) == 0x04034b50) {
    final flags = data.getUint16(offset + 6, Endian.little),
        method = data.getUint16(offset + 8, Endian.little),
        size = data.getUint32(offset + 18, Endian.little),
        expanded = data.getUint32(offset + 22, Endian.little),
        nameSize = data.getUint16(offset + 26, Endian.little),
        extra = data.getUint16(offset + 28, Endian.little);
    final start = offset + 30 + nameSize + extra, end = start + size;
    if (flags != 0x800 || method != 0 || size != expanded || end > zip.length) {
      throw const FormatException('官网压缩包格式无效');
    }
    final name = utf8.decode(zip.sublist(offset + 30, offset + 30 + nameSize));
    if (name == 'SD/M10V/FILMS.M10') {
      if (pack != null) throw const FormatException('胶卷库重复');
      pack = Uint8List.sublistView(zip, start, end);
      if (filmCrc(pack) != data.getUint32(offset + 14, Endian.little)) {
        throw const FormatException('压缩包校验失败');
      }
    }
    offset = end;
  }
  if (pack == null) throw const FormatException('未找到胶卷库文件');
  return pack;
}

class OfficialFilmSnapshot {
  const OfficialFilmSnapshot(this.films, this.updatedAt, this.sha256);
  final List<OfficialFilm> films;
  final DateTime updatedAt;
  final String sha256;
}

class OfficialFilmLibrary {
  OfficialFilmLibrary(
      {required http.Client client,
      required Future<Directory> Function() directory})
      : _client = client,
        _directory = directory;
  final http.Client _client;
  final Future<Directory> Function() _directory;
  Future<File> get _cache async =>
      File('${(await _directory()).path}/official-library.json');
  Future<Uint8List> _request(String path,
      {Map<String, String> headers = const {}, String? body}) async {
    final request = http.Request(
        body == null ? 'GET' : 'POST', Uri.parse('$officialFilmOrigin$path'))
      ..followRedirects = false
      ..headers.addAll(headers);
    if (body != null) request.body = body;
    final response =
        await _client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException('官网暂时无法连接（${response.statusCode}）');
    }
    final result = BytesBuilder(copy: false);
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 30))) {
      result.add(chunk);
      if (result.length > 4 * 1024 * 1024) {
        throw const FormatException('官网响应过大');
      }
    }
    return result.takeBytes();
  }

  Future<OfficialFilmSnapshot?> cached({String? expectedRenderer}) async {
    final cache = await _cache;
    if (!await cache.exists()) return null;
    try {
      if (await cache.length() > 6 * 1024 * 1024) return null;
      final json = jsonDecode(await cache.readAsString()) as Map;
      final films = parseOfficialCatalog(json['catalog'] as String),
          pack = base64Decode(json['pack'] as String);
      await Isolate.run(() => validateOfficialPack(
          pack, films.map((f) => f.id).toSet(),
          expectedRenderer: expectedRenderer));
      final hash = sha256.convert(pack).toString();
      if (hash != json['hash']) return null;
      return OfficialFilmSnapshot(
          films, DateTime.parse(json['updatedAt'] as String), hash);
    } catch (_) {
      return null;
    }
  }

  Future<OfficialFilmSnapshot> sync({required String expectedRenderer}) async {
    final source =
        utf8.decode(await _request('/api/gr3/native-library/catalog'));
    final films = parseOfficialCatalog(source);
    final status =
        jsonDecode(utf8.decode(await _request('/api/status'))) as Map;
    final token = status['session_token'];
    if (token is! String || token.isEmpty || token.length > 256) {
      throw const FormatException('官网会话无效');
    }
    final zip = await _request('/api/gr3/sd-library/export',
        headers: {
          'Origin': officialFilmOrigin,
          'X-M10V-Token': token,
          'Content-Type': 'application/json'
        },
        body: jsonEncode(
            {'model': 'gr3', 'ids': films.map((f) => f.id).toList()}));
    final pack = await Isolate.run(() => officialPackFromZip(zip));
    await Isolate.run(() => validateOfficialPack(
        pack, films.map((f) => f.id).toSet(),
        expectedRenderer: expectedRenderer));
    final hash = sha256.convert(pack).toString(),
        at = DateTime.now().toUtc(),
        cache = await _cache;
    await cache.parent.create(recursive: true);
    final staging = File('${cache.path}.tmp');
    try {
      await staging.writeAsString(
          jsonEncode({
            'catalog': source,
            'pack': base64Encode(pack),
            'hash': hash,
            'updatedAt': at.toIso8601String()
          }),
          flush: true);
      await staging.rename(cache.path);
    } finally {
      if (await staging.exists()) await staging.delete();
    }
    return OfficialFilmSnapshot(films, at, hash);
  }
}
