import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'official_film_luts.dart';
import 'official_lut_cache.dart';

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
        id > 0xffffffff ||
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

String validateOfficialPack(List<int> input, Set<int> expectedIds,
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
  String? packRenderer;
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
        (packRenderer == null || renderer == packRenderer) &&
        (expectedRenderer == null || renderer == expectedRenderer));
    packRenderer = renderer;
  }
  return packRenderer!;
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
  const OfficialFilmSnapshot(this.films, this.updatedAt, this.sha256,
      {required this.rendererHash,
      required this.cameraCompatible,
      this.phoneLuts = const []});
  final List<OfficialFilm> films;
  final DateTime updatedAt;
  final String sha256;
  final String rendererHash;
  final bool cameraCompatible;
  final List<OfficialLutRecord> phoneLuts;
}

Set<String> _colorSources(List<OfficialFilm> films) => {
      for (final f in films)
        if (f.id >= 34 && f.id <= 65)
          '/gr3/film-catalog.json'
        else if (f.id == 66)
          '/gr3/5207-lut.json'
        else if (f.id == 67 || f.id == 68)
          '/gr3/harman-luts.json'
        else if (f.id >= 69 && f.id <= 72)
          '/gr3/curated-luts.json'
        else if (f.id >= 73 && f.id <= 78)
          '/gr3/newstocks-luts.json'
        else if (f.id >= 291 && f.id <= 297)
          '/gr3/style-filters-luts.json'
        else if (f.id == 298)
          '/gr3/spectral-luts.json'
        else if (f.id >= 299 && f.id <= 305)
          '/gr3/d76-luts.json'
        else if (f.id >= 309 && f.id <= 311)
          '/gr3/anime-e6-luts.json'
        else if (f.id == 312 || f.id == 313 || f.id >= 322 && f.id <= 326)
          '/gr3/c41-luts.json'
        else if (f.id >= 314 && f.id <= 317)
          '/gr3/extra-films-luts.json'
        else if (f.id >= 318 && f.id <= 321)
          '/gr3/four-looks-luts.json'
    };

void _checkColorBindings(Uint8List pack,
    Map<String, Map<String, dynamic>> sources, List<OfficialFilm> films) {
  final header = ByteData.sublistView(pack);
  final records = <int, int>{
    for (var i = 0; i < films.length; i++)
      header.getUint32(64 + i * 12, Endian.little): 4096 + i * 12288,
  };
  // These families bind their numeric target tables in each closed SD record.
  // Detect a deployment changing between the pack and static-data requests.
  for (final entry in sources.entries) {
    if (!const {
      '/gr3/style-filters-luts.json',
      '/gr3/spectral-luts.json',
      '/gr3/d76-luts.json',
      '/gr3/anime-e6-luts.json',
      '/gr3/c41-luts.json',
      '/gr3/extra-films-luts.json',
      '/gr3/four-looks-luts.json',
    }.contains(entry.key)) continue;
    final native = const {
      '/gr3/anime-e6-luts.json',
      '/gr3/c41-luts.json',
      '/gr3/extra-films-luts.json',
      '/gr3/four-looks-luts.json',
    }.contains(entry.key);
    for (final stock in entry.value['stocks'] as List) {
      if (entry.key == '/gr3/spectral-luts.json' && stock['id'] != 298) {
        continue;
      }
      final offset = records[stock['id']];
      if (offset == null) continue;
      final values =
          (stock[native ? 'native_values' : 'values'] as List).cast<int>();
      final digest = sha256.convert(values).bytes;
      if (!List.generate(32, (i) => digest[i] == pack[offset + 64 + i])
          .every((v) => v)) {
        throw FormatException('官网胶卷数据已变化（${stock['id']}），请重新同步');
      }
    }
  }
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

  /// The same validated payload can be copied through the phone's system file
  /// picker. This does not authorize an arbitrary camera network upload.
  Future<Uint8List> exportPack() async {
    final snapshot = await cached();
    if (snapshot == null) throw const FormatException('请先同步官网胶卷库');
    final raw = jsonDecode(await (await _cache).readAsString()) as Map;
    final bytes = base64Decode(raw['pack'] as String);
    validateOfficialPack(bytes, snapshot.films.map((f) => f.id).toSet());
    if (sha256.convert(bytes).toString() != snapshot.sha256) {
      throw const FormatException('胶卷库已变化，请重新同步');
    }
    return bytes;
  }

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
      final renderer = await Isolate.run(
          () => validateOfficialPack(pack, films.map((f) => f.id).toSet()));
      final hash = sha256.convert(pack).toString();
      if (hash != json['hash']) return null;
      return OfficialFilmSnapshot(
          films, DateTime.parse(json['updatedAt'] as String), hash,
          rendererHash: renderer,
          cameraCompatible: renderer == expectedRenderer,
          phoneLuts: await OfficialLutCache(directory: _directory).entries());
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
    // The website catalogue can advance independently of paired firmware.
    // Validate every record, but expose compatibility separately for write UI.
    final renderer = await Isolate.run(
        () => validateOfficialPack(pack, films.map((f) => f.id).toSet()));
    final sources = <String, Map<String, dynamic>>{};
    final paths = _colorSources(films).toList();
    // Bounded parallel reads. No remote executable code is loaded.
    var sourceBytes = 0;
    for (var i = 0; i < paths.length; i += 3) {
      final batch = paths.skip(i).take(3).toList();
      final fetched = await Future.wait(batch.map(_request));
      for (var n = 0; n < batch.length; n++) {
        sourceBytes += fetched[n].length;
        if (sourceBytes > 16 * 1024 * 1024) {
          throw const FormatException('官网色彩数据过大');
        }
        final data = jsonDecode(utf8.decode(fetched[n]));
        if (data is! Map<String, dynamic>) {
          throw const FormatException('官网色彩数据格式无效');
        }
        sources[batch[n]] = data;
      }
    }
    final colors = await Isolate.run(
        () => compileOfficialFilmLuts(films: films, sources: sources));
    await Isolate.run(() => _checkColorBindings(pack, sources, films));
    final phoneLuts =
        await OfficialLutCache(directory: _directory).stage(colors);
    final hash = sha256.convert(pack).toString(),
        at = DateTime.now().toUtc(),
        cache = await _cache;
    await cache.parent.create(recursive: true);
    final staging = File('${cache.path}.${at.microsecondsSinceEpoch}.tmp');
    try {
      await staging.writeAsString(
          jsonEncode({
            'catalog': source,
            'pack': base64Encode(pack),
            'hash': hash,
            'updatedAt': at.toIso8601String(),
            'phoneLuts': phoneLuts,
          }),
          flush: true);
      await staging.rename(cache.path);
    } finally {
      if (await staging.exists()) await staging.delete();
    }
    return OfficialFilmSnapshot(films, at, hash,
        rendererHash: renderer,
        cameraCompatible: renderer == expectedRenderer,
        phoneLuts:
            phoneLuts.map(OfficialLutRecord.fromJson).toList(growable: false));
  }
}
