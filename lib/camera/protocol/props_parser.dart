import 'package:meta/meta.dart';

/// Status fields reported next to the parameters in `/v1/props`.
@immutable
class CameraStatus {
  const CameraStatus({
    this.battery,
    this.hot,
    this.remain,
    this.liveState,
    this.captureState,
    this.captureId,
  });

  final int? battery;
  final bool? hot;

  /// Remaining shots on the first writable storage.
  final int? remain;
  final String? liveState;
  final String? captureState;
  final String? captureId;

  /// Fields present in [other] replace ours.
  CameraStatus merge(CameraStatus other) => CameraStatus(
        battery: other.battery ?? battery,
        hot: other.hot ?? hot,
        remain: other.remain ?? remain,
        liveState: other.liveState ?? liveState,
        captureState: other.captureState ?? captureState,
        captureId: other.captureId ?? captureId,
      );
}

/// A value and/or option list seen in one props payload.
@immutable
class ParsedParam {
  const ParsedParam({this.current, this.options});

  final String? current;
  final List<String>? options;
}

@immutable
class ParsedProps {
  const ParsedProps({
    required this.params,
    required this.status,
    required this.keyTypes,
  });

  /// Keyed by wire key; includes every scalar and every `xxxList`.
  final Map<String, ParsedParam> params;
  final CameraStatus status;

  /// Top-level key → JSON type name, for the protocol probe.
  final Map<String, String> keyTypes;
}

const _statusKeys = {
  'battery',
  'hot',
  'storages',
  'liveState',
  'state',
  'captureId',
};

/// Tolerant `/v1/props` parser (firmware-derived / hardware-unverified).
///
/// Unknown keys, missing keys and unexpected types never throw.
ParsedProps parseProps(Map<String, Object?> json) {
  final currents = <String, String>{};
  final lists = <String, List<String>>{};
  final keyTypes = <String, String>{};
  for (final MapEntry(:key, :value) in json.entries) {
    keyTypes[key] = _typeName(value);
    if (_statusKeys.contains(key)) continue;
    if (key.endsWith('List') && key.length > 4) {
      if (value is! List) continue;
      lists[key.substring(0, key.length - 4)] = [
        for (final item in value)
          if (_isScalar(item)) '$item'
      ];
    } else if (_isScalar(value)) {
      currents[key] = '$value';
    }
  }
  return ParsedProps(
    params: {
      for (final key in {...currents.keys, ...lists.keys})
        key: ParsedParam(current: currents[key], options: lists[key]),
    },
    status: _status(json),
    keyTypes: keyTypes,
  );
}

CameraStatus _status(Map<String, Object?> json) {
  final battery = json['battery'];
  final level = switch (battery) {
    num() => battery.toInt(),
    {'level': final num value} => value.toInt(),
    _ => null,
  };
  int? remain;
  final storages = json['storages'];
  if (storages is List) {
    for (final storage in storages) {
      if (storage case {'remain': final num value}) {
        remain = value.toInt();
        break;
      }
    }
  }
  final hot = json['hot'];
  return CameraStatus(
    battery: level,
    hot: hot is bool ? hot : null,
    remain: remain,
    liveState: _scalar(json['liveState']),
    captureState: _scalar(json['state']),
    captureId: _scalar(json['captureId']),
  );
}

bool _isScalar(Object? value) =>
    value is String || value is num || value is bool;

String? _scalar(Object? value) => _isScalar(value) ? '$value' : null;

String _typeName(Object? value) => switch (value) {
      null => 'null',
      String() => 'string',
      num() => 'number',
      bool() => 'bool',
      List() => 'list',
      Map() => 'object',
      _ => 'unknown',
    };
