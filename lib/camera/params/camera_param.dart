import 'package:meta/meta.dart';

/// Which `PUT /v1/params/<endpoint>` route accepts a parameter.
enum ParamEndpoint { camera, lens }

/// Parameters gremote renders with dedicated controls.
///
/// Wire keys are firmware-derived (`webapid` strings) / hardware-unverified.
enum ParamKey {
  aperture('av'),
  shutter('tv'),
  iso('sv'),
  exposureComp('xv'),
  whiteBalance('WBMode'),
  metering('meteringMode'),
  focusSetting('focusSetting', endpoint: ParamEndpoint.lens),
  exposureMode('exposureMode', readOnly: true),
  drive('shootMode'),
  effect('effect'),
  aspectRatio('aspectRatio'),
  stillFormat('stillFormat');

  const ParamKey(
    this.wireKey, {
    this.endpoint = ParamEndpoint.camera,
    this.readOnly = false,
  });

  final String wireKey;
  final ParamEndpoint endpoint;

  /// The physical mode dial owns this value.
  final bool readOnly;

  String get listKey => '${wireKey}List';

  static ParamKey? fromWire(String wireKey) {
    for (final key in values) {
      if (key.wireKey == wireKey) return key;
    }
    return null;
  }
}

/// One camera parameter as last reported by the camera.
@immutable
class CameraParam {
  const CameraParam({
    required this.wireKey,
    this.current,
    this.options = const [],
    this.endpoint = ParamEndpoint.camera,
    this.readOnly = false,
  });

  factory CameraParam.forWire(String wireKey,
      {String? current, List<String> options = const []}) {
    final key = ParamKey.fromWire(wireKey);
    return CameraParam(
      wireKey: wireKey,
      current: current,
      options: options,
      endpoint: key?.endpoint ?? ParamEndpoint.camera,
      readOnly: key?.readOnly ?? false,
    );
  }

  final String wireKey;

  /// Raw camera string; never reformatted.
  final String? current;

  /// Camera order; an empty or single-item list means "not writable now".
  final List<String> options;
  final ParamEndpoint endpoint;
  final bool readOnly;

  ParamKey? get key => ParamKey.fromWire(wireKey);

  bool get writable => !readOnly && options.length >= 2;

  CameraParam copyWith({String? current, List<String>? options}) => CameraParam(
        wireKey: wireKey,
        current: current ?? this.current,
        options: options ?? this.options,
        endpoint: endpoint,
        readOnly: readOnly,
      );

  @override
  String toString() => 'CameraParam($wireKey: $current, ${options.length})';
}
