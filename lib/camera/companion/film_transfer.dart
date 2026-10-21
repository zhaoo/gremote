import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../film/model/film_recipe.dart';

/// Data-only portable custom film; validates all canonical record fields.
class FilmTransfer {
  FilmTransfer._(this.stableId, this.rendererHash, this.contentHash, this.name,
      Uint8List record)
      : _record = record.asUnmodifiableView();
  final int stableId;
  final String rendererHash, contentHash, name;
  final Uint8List _record;
  static FilmTransfer parse(Uint8List bytes,
      {required String expectedRenderer}) {
    void need(bool ok) {
      if (!ok) throw const FormatException('胶卷数据损坏或与当前渲染版本不匹配');
    }

    need(bytes.isNotEmpty && bytes.length <= 18432);
    final raw = jsonDecode(utf8.decode(bytes));
    need(raw is Map &&
        raw.length == 3 &&
        raw['schema'] == 'm10v.film-transfer/v1' &&
        raw['metadata'] is Map &&
        raw['recordBase64'] is String);
    final value = raw as Map, meta = value['metadata'] as Map;
    need(meta.length == 7 &&
        meta.keys.every((k) => {
              'model',
              'schema',
              'stableId',
              'rendererHash',
              'contentHash',
              'size',
              'chunkBytes'
            }.contains(k)) &&
        meta['model'] == 'GR III' &&
        meta['schema'] == 1 &&
        meta['stableId'] is int &&
        (meta['stableId'] as int) >= 79 &&
        (meta['stableId'] as int) <= 288 &&
        meta['size'] == 12288 &&
        meta['chunkBytes'] == 4096 &&
        meta['rendererHash'] == expectedRenderer &&
        meta['contentHash'] is String &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(meta['contentHash'] as String));
    final encoded = value['recordBase64'] as String,
        record = base64Decode(encoded);
    need(record.length == 12288 &&
        base64Encode(record) == encoded &&
        sha256.convert(record).toString() == meta['contentHash']);
    final data = ByteData.sublistView(record);
    need(ascii.decode(record.sublist(0, 8), allowInvalid: true) == 'M10VREC2' &&
        data.getUint32(8, Endian.little) == meta['stableId'] &&
        data.getUint32(12, Endian.little) == 4);
    var end = 16;
    while (end < 40 && record[end] != 0) {
      need(record[end] >= 32 && record[end] <= 126);
      end++;
    }
    need(end > 16 && end < 40);
    final name = ascii.decode(record.sublist(16, end));
    bool zero(int a, int b) => record.sublist(a, b).every((v) => v == 0);
    need(zero(end, 40) &&
        ascii.decode(record.sublist(40, 44), allowInvalid: true) == 'M10V' &&
        zero(44, 64) &&
        record[6655] == 0 &&
        zero(6688, 8448) &&
        zero(8480, 12284));
    String hex(List<int> bytes) =>
        bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    need(hex(record.sublist(8448, 8480)) == expectedRenderer &&
        hex(record.sublist(6656, 6688)) ==
            sha256.convert([
              ...ascii.encode(name),
              0,
              ...record.sublist(64, 6655)
            ]).toString());
    var crc = 0xffffffff;
    for (final byte in record.sublist(0, 12284)) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
      }
    }
    need((~crc & 0xffffffff) == data.getUint32(12284, Endian.little));
    return FilmTransfer._(meta['stableId'] as int, expectedRenderer,
        meta['contentHash'] as String, name, record);
  }

  Uint8List chunk(int index) {
    if (index < 0 || index > 2) throw RangeError.index(index, [0, 1, 2]);
    return Uint8List.sublistView(_record, index * 4096, (index + 1) * 4096);
  }

  FilmRecipe recipe(String catalogHash) => FilmRecipe.fromJson({
        'schemaVersion': 1,
        'filmId': stableId,
        'catalogHash': catalogHash,
        'rendererHash': rendererHash,
        'customHash': contentHash,
        'parameters': <String, int>{},
        'name': name
      });
}
