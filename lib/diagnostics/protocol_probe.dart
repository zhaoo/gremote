import 'dart:async';

import 'package:meta/meta.dart';

import '../camera/gateway/change_socket.dart';
import '../camera/http/camera_api.dart';
import '../camera/params/camera_param.dart';
import '../camera/protocol/props_parser.dart';
import '../camera/protocol/protocol_profile.dart';

@immutable
class ProbeReport {
  const ProbeReport({
    required this.routes,
    required this.keyTypes,
    required this.lists,
    required this.webSocket,
    required this.eventsInWindow,
    this.writeResults,
  });

  final Map<String, int?> routes;
  final Map<String, String> keyTypes;

  /// Base parameter key → raw camera option strings.
  final Map<String, List<String>> lists;
  final WsSupport webSocket;
  final int eventsInWindow;
  final Map<WriteEncoding, bool>? writeResults;

  WriteEncoding get preferredEncoding {
    final results = writeResults;
    if (results == null) return WriteEncoding.unknown;
    for (final encoding in const [
      WriteEncoding.query,
      WriteEncoding.form,
      WriteEncoding.json,
    ]) {
      if (results[encoding] == true) return encoding;
    }
    return WriteEncoding.unknown;
  }

  Map<String, Object?> toJson() => {
        'routes': routes,
        'keyTypes': keyTypes,
        'lists': lists,
        'webSocket': webSocket.name,
        'eventsInWindow': eventsInWindow,
        if (writeResults != null)
          'writeResults': {
            for (final MapEntry(:key, :value) in writeResults!.entries)
              key.name: value,
          },
      };
}

/// Conservative, redacted protocol probe. It never records prop values; the
/// optional write phase only writes the current exposure compensation back.
class ProtocolProbe {
  ProtocolProbe({
    required CameraApi api,
    required ChangeSocket socket,
    this.listen = const Duration(seconds: 10),
  })  : _api = api,
        _socket = socket;

  final CameraApi _api;
  final ChangeSocket _socket;
  final Duration listen;

  Future<ProbeReport> run({required bool includeWrite}) async {
    final routes = <String, int?>{};
    await _route(routes, '/v1/ping', _api.ping);

    Map<String, Object?> props = const {};
    await _route(routes, '/v1/props', () async {
      props = await _api.props();
      return props;
    });
    await _route(routes, '/v1/debug/revisions', _api.revisions);
    await _route(routes, '/v1/photos', () async {
      final files = await _api.photos();
      routes['/v1/photos#count'] = files.length;
      return const <String, Object?>{};
    });

    final parsed = parseProps(props);
    final lists = <String, List<String>>{
      for (final MapEntry(:key, :value) in parsed.params.entries)
        if (value.options != null) key: List.unmodifiable(value.options!),
    };
    final socketResult = await _probeSocket();
    final writes = includeWrite ? await _probeWrites(props) : null;
    return ProbeReport(
      routes: routes,
      keyTypes: parsed.keyTypes,
      lists: lists,
      webSocket: socketResult.$1,
      eventsInWindow: socketResult.$2,
      writeResults: writes,
    );
  }

  Future<void> _route(
    Map<String, int?> routes,
    String path,
    Future<Map<String, Object?>> Function() action,
  ) async {
    try {
      await action();
      routes[path] = 200;
    } on CameraApiException catch (error) {
      routes[path] = error.statusCode;
    } on Exception {
      routes[path] = null;
    }
  }

  Future<(WsSupport, int)> _probeSocket() async {
    var support = WsSupport.unknown;
    var events = 0;
    final subscription = _socket.events.listen((event) {
      switch (event) {
        case ChangeSocketOpened():
          support = WsSupport.supported;
        case ChangeSocketMessage():
          events++;
        case ChangeSocketFailed() || ChangeSocketClosed():
          if (support != WsSupport.supported) support = WsSupport.unsupported;
      }
    });
    try {
      await _socket.open('/v1/changes');
      await Future<void>.delayed(listen);
      await Future<void>.delayed(Duration.zero);
    } on Exception {
      support = WsSupport.unsupported;
    } finally {
      await _socket.close();
      await subscription.cancel();
    }
    return (support, events);
  }

  Future<Map<WriteEncoding, bool>> _probeWrites(
      Map<String, Object?> initialProps) async {
    final current = initialProps['xv'];
    if (current is! String && current is! num) {
      return {
        WriteEncoding.query: false,
        WriteEncoding.form: false,
        WriteEncoding.json: false,
      };
    }
    final value = '$current';
    final results = <WriteEncoding, bool>{};
    for (final encoding in const [
      WriteEncoding.query,
      WriteEncoding.form,
      WriteEncoding.json,
    ]) {
      var ok = false;
      try {
        await _api.putParams(ParamEndpoint.camera, {'xv': value}, encoding);
        final readback = await _api.props();
        ok = '${readback['xv']}' == value;
        if (!ok) {
          // Best effort rollback using the same encoding that just succeeded.
          await _api.putParams(ParamEndpoint.camera, {'xv': value}, encoding);
        }
      } on Exception {
        ok = false;
      }
      results[encoding] = ok;
    }
    return results;
  }
}
