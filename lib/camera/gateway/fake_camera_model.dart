import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../http/camera_files.dart';
import 'camera_transport.dart';
import 'change_socket.dart';

/// Programmable stand-in for a GR III's Wi-Fi API, used by tests and the
/// `GREMOTE_FAKE_CAMERA` build. Shapes follow the firmware-derived guesses.
class FakeCameraModel {
  FakeCameraModel({
    Map<String, Object?>? props,
    this.acceptedContentTypes = const {'query', 'form', 'json'},
    this.webSocket = true,
    DateTime Function()? clock,
  })  : props = props ?? defaultProps(),
        _clock = clock ?? DateTime.now;

  static Map<String, Object?> defaultProps() => {
        'model': 'RICOH GR III',
        'firmwareVersion': '2.10',
        'battery': 82,
        'hot': false,
        'liveState': 'on',
        'storages': [
          {'storageId': 'storage0', 'remain': 812},
        ],
        'exposureMode': 'M',
        'exposureModeList': ['M'],
        'av': '2.8',
        'avList': ['2.8', '3.5', '4.0', '5.6', '8.0', '11', '16'],
        'tv': '1/250',
        'tvList': [
          '1/4000',
          '1/2000',
          '1/1000',
          '1/500',
          '1/250',
          '1/125',
          '1/60',
          '1/30',
          '1/15',
          '1/8',
          '1/4',
          '1/2',
          '1',
          '2',
          '4',
          '8',
          '15',
          '30',
        ],
        'sv': '200',
        'svList': ['auto', '100', '200', '400', '800', '1600', '3200', '6400'],
        'xv': '0.0',
        'xvList': ['-1.0', '-0.7', '-0.3', '0.0', '+0.3', '+0.7', '+1.0'],
        'WBMode': 'auto',
        'WBModeList': ['auto', 'daylight', 'shade', 'cloud', 'tungsten'],
        'meteringMode': 'multi',
        'meteringModeList': ['multi', 'center', 'spot', 'highlight'],
        'focusSetting': 'af',
        'focusSettingList': ['af', 'mf', 'snap', 'infinity'],
        'shootMode': 'single',
        'shootModeList': [
          'single',
          'continuous',
          'self2s',
          'self10s',
          'bracket',
          'dofBracket',
          'interval',
          'intervalComp',
          'intervalMovie',
        ],
        'effect': 'standard',
        'effectList': [
          'standard',
          'vivid',
          'monotone',
          'softMonotone',
          'hardMonotone',
          'positiveFilm',
          'bleachBypass',
          'retro',
          'negativeFilm',
        ],
        'aspectRatio': '3:2',
        'aspectRatioList': ['3:2', '1:1', '16:9'],
        'stillFormat': 'jpeg',
        'stillFormatList': ['jpeg', 'rawdng+jpeg'],
        'noiseReduction': 'auto',
        'noiseReductionList': ['auto', 'low', 'high', 'off'],
      };

  final Map<String, Object?> props;

  /// Which write encodings succeed: `query`, `form`, `json`.
  Set<String> acceptedContentTypes;

  /// Whether `/v1/changes` upgrades.
  bool webSocket;
  final DateTime Function() _clock;

  final files = <CameraFile>[];
  final writes = <String>[];
  final _times = <String, DateTime>{};
  var _counter = 0;
  var _socketOpen = false;
  final _socket = StreamController<ChangeSocketEvent>.broadcast();

  Stream<ChangeSocketEvent> get socketEvents => _socket.stream;
  bool get socketOpen => _socketOpen;

  CameraResponse handle(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Uint8List? body,
  }) {
    final uri = Uri.parse(path);
    final route = uri.path;
    if (route == '/v1/ping') return _json({'pong': true});
    if (route == '/v1/props') return _json(props);
    if (route == '/v1/debug/revisions') return _json({'webapi': 'fake'});
    if (route == '/v1/photos') return _json(_photoList());
    if (method == 'PUT' && route.startsWith('/v1/params/')) {
      return _write(uri, headers, body);
    }
    if (method == 'POST' && route == '/v1/camera/shoot') {
      shutter();
      return _json({'errCode': 200, 'errMsg': 'OK'});
    }
    if (route.startsWith('/v1/photos/')) return _photo(uri);
    return _json({'errCode': 200, 'errMsg': 'OK'});
  }

  /// A shot taken on the camera (body button or HTTP).
  void shutter() {
    _counter++;
    final base = 'R${_counter.toString().padLeft(7, '0')}';
    files.add(CameraFile(dir: '100RICOH', file: '$base.JPG'));
    if ('${props['stillFormat']}'.contains('raw')) {
      files.add(CameraFile(dir: '100RICOH', file: '$base.DNG'));
    }
    final storages = props['storages']! as List;
    final storage = storages.first as Map<String, Object?>;
    final remain = (storage['remain']! as int) - 1;
    storage['remain'] = remain;
    _times[base] = _clock();
    _push({
      'captureId': '$_counter',
      'state': 'idle',
      'storages': [
        {'remain': remain},
      ],
    });
  }

  /// Changes a value as if the user turned a dial on the body.
  void bodyChange(String key, String value) {
    props[key] = value;
    _push({key: value});
  }

  Future<void> openSocket(String path) async {
    await Future<void>.delayed(Duration.zero);
    if (path != '/v1/changes' || !webSocket) {
      _socket.add(const ChangeSocketFailed(404));
      return;
    }
    _socketOpen = true;
    _socket.add(const ChangeSocketOpened());
  }

  Future<void> closeSocket() async => _socketOpen = false;

  /// Drops the socket from the camera side.
  void dropSocket() {
    if (!_socketOpen) return;
    _socketOpen = false;
    _socket.add(const ChangeSocketClosed(1006));
  }

  void dispose() => unawaited(_socket.close());

  void _push(Map<String, Object?> change) {
    if (_socketOpen) _socket.add(ChangeSocketMessage(jsonEncode(change)));
  }

  CameraResponse _write(Uri uri, Map<String, String> headers, Uint8List? body) {
    final contentType = headers['Content-Type'] ?? '';
    final (kind, values) = switch (contentType) {
      'application/json' => (
          'json',
          (jsonDecode(utf8.decode(body!)) as Map<String, Object?>)
              .map((k, v) => MapEntry(k, '$v')),
        ),
      'application/x-www-form-urlencoded' => (
          'form',
          Uri.splitQueryString(utf8.decode(body!)),
        ),
      _ => ('query', uri.queryParameters),
    };
    if (!acceptedContentTypes.contains(kind) || values.isEmpty) {
      return _json({'errCode': 400, 'errMsg': 'Bad request'}, status: 400);
    }
    for (final MapEntry(:key, :value) in values.entries) {
      final options = props['${key}List'];
      if (key == 'exposureMode' ||
          options is! List ||
          options.length < 2 ||
          !options.contains(value)) {
        return _json({'errCode': 400, 'errMsg': 'Invalid value'}, status: 400);
      }
    }
    for (final MapEntry(:key, :value) in values.entries) {
      props[key] = value;
      writes.add('$key=$value');
      _push({key: value});
    }
    return _json({'errCode': 200, 'errMsg': 'OK'});
  }

  Map<String, Object?> _photoList() {
    final dirs = <String, List<String>>{};
    for (final file in files) {
      dirs.putIfAbsent(file.dir, () => []).add(file.file);
    }
    return {
      'errCode': 200,
      'dirs': [
        for (final MapEntry(:key, :value) in dirs.entries)
          {'name': key, 'files': value},
      ],
    };
  }

  CameraResponse _photo(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length < 4) return _json({}, status: 404);
    final file = CameraFile(dir: segments[2], file: segments[3]);
    if (!files.contains(file)) return _json({}, status: 404);
    if (segments.length == 5 && segments[4] == 'info') {
      final t = _times[file.baseName] ?? _clock();
      return _json({
        'errCode': 200,
        'datetime': '${t.year.toString().padLeft(4, '0')}-'
            '${_two(t.month)}-${_two(t.day)}T'
            '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}',
        'effect': props['effect'],
      });
    }
    return CameraResponse(
      statusCode: 200,
      headers: const {'content-type': 'image/jpeg'},
      body: base64Decode(fakeJpegBase64),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static CameraResponse _json(Object payload, {int status = 200}) =>
      CameraResponse(
        statusCode: status,
        headers: const {'content-type': 'application/json'},
        body: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      );
}

/// A 1×1 JPEG used for fake Live View frames and thumbnails.
const fakeJpegBase64 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkS'
    'Ew8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJ'
    'CQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy'
    'MjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEA'
    'AAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIh'
    'MUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6'
    'Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZ'
    'mqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx'
    '8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREA'
    'AgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAV'
    'YnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hp'
    'anN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPE'
    'xcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDx'
    'Siiiuk5z/9k=';
