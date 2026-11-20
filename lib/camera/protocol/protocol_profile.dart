import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sqflite/sqflite.dart';

import '../../darkroom/darkroom_providers.dart';

enum WriteEncoding { query, form, json, unknown }

enum WsSupport { supported, unsupported, unknown }

/// What gremote has learned about this firmware's HTTP behaviour.
@immutable
class ProtocolProfile {
  const ProtocolProfile({
    required this.firmware,
    this.model = '',
    this.writeEncoding = WriteEncoding.unknown,
    this.webSocket = WsSupport.unknown,
    this.probedAt,
  });

  factory ProtocolProfile.fromJson(Map<String, Object?> json) =>
      ProtocolProfile(
        firmware: json['firmware'] as String? ?? 'unknown',
        model: json['model'] as String? ?? '',
        writeEncoding: _byName(
            WriteEncoding.values, json['writeEncoding'], WriteEncoding.unknown),
        webSocket:
            _byName(WsSupport.values, json['webSocket'], WsSupport.unknown),
        probedAt: switch (json['probedAt']) {
          final String value => DateTime.tryParse(value),
          _ => null,
        },
      );

  final String firmware;
  final String model;
  final WriteEncoding writeEncoding;
  final WsSupport webSocket;
  final DateTime? probedAt;

  Map<String, Object?> toJson() => {
        'firmware': firmware,
        if (model.isNotEmpty) 'model': model,
        'writeEncoding': writeEncoding.name,
        'webSocket': webSocket.name,
        'probedAt': probedAt?.toIso8601String(),
      };

  ProtocolProfile copyWith({
    WriteEncoding? writeEncoding,
    WsSupport? webSocket,
    DateTime? probedAt,
  }) =>
      ProtocolProfile(
        firmware: firmware,
        model: model,
        writeEncoding: writeEncoding ?? this.writeEncoding,
        webSocket: webSocket ?? this.webSocket,
        probedAt: probedAt ?? this.probedAt,
      );
}

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

final protocolProfileStoreProvider = Provider<ProtocolProfileStore>(
    (ref) => ProtocolProfileStore(ref.watch(databaseProvider)));

class ProtocolProfileStore {
  ProtocolProfileStore(this._db);

  final Database _db;

  static String _key(String firmware, String model) =>
      model.isEmpty || model == 'RICOH GR III'
          ? 'protocolProfile:$firmware'
          : 'protocolProfile:$model:$firmware';

  Future<ProtocolProfile> load(String firmware, {String model = ''}) async {
    final rows = await _db.query('app_kv',
        where: 'key = ?', whereArgs: [_key(firmware, model)], limit: 1);
    if (rows.isEmpty) return ProtocolProfile(firmware: firmware, model: model);
    try {
      final json = jsonDecode(rows.single['value']! as String);
      if (json is Map<String, Object?>) {
        return ProtocolProfile.fromJson(
            {...json, 'firmware': firmware, 'model': model});
      }
    } on FormatException {
      // Fall through to a fresh profile.
    }
    return ProtocolProfile(firmware: firmware, model: model);
  }

  Future<void> save(ProtocolProfile profile) => _db.insert(
        'app_kv',
        {
          'key': _key(profile.firmware, profile.model),
          'value': jsonEncode(profile.toJson())
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}
