import 'dart:async';

import '../http/camera_api.dart';
import '../protocol/protocol_profile.dart';
import 'camera_param.dart';

sealed class WriteOutcome {
  const WriteOutcome();
}

class WriteConfirmed extends WriteOutcome {
  const WriteConfirmed(this.value);
  final String value;
}

/// The camera accepted the write but settled on another value.
class WriteCorrected extends WriteOutcome {
  const WriteCorrected(this.actual);
  final String actual;
}

class WriteRejected extends WriteOutcome {
  const WriteRejected(this.code, [this.message]);
  final String code;
  final String? message;
}

class WriteTimedOut extends WriteOutcome {
  const WriteTimedOut();
}

/// A newer value for the same parameter replaced this one in the queue.
class WriteSuperseded extends WriteOutcome {
  const WriteSuperseded();
}

/// No write encoding works on this firmware; read-only for this connection.
class WritesDisabled extends WriteOutcome {
  const WritesDisabled();
}

typedef SendParams = Future<Map<String, Object?>> Function(
    ParamEndpoint endpoint, Map<String, String> values, WriteEncoding encoding);

const _fallbackOrder = [
  WriteEncoding.query,
  WriteEncoding.form,
  WriteEncoding.json
];

class _Job {
  _Job(this.param, this.value);

  final CameraParam param;
  final String value;
  final completer = Completer<WriteOutcome>();
}

/// Serialises parameter writes: one request in flight, at most one queued
/// value per parameter (newest wins), camera readback decides the result.
class ParamWriter {
  ParamWriter({
    required SendParams send,
    required Future<String?> Function(String wireKey) refreshAndRead,
    required WriteEncoding Function() encoding,
    required Future<void> Function(WriteEncoding) rememberEncoding,
    required void Function() disableWrites,
    this.timeout = const Duration(seconds: 3),
  })  : _send = send,
        _refreshAndRead = refreshAndRead,
        _encoding = encoding,
        _rememberEncoding = rememberEncoding,
        _disableWrites = disableWrites;

  final SendParams _send;
  final Future<String?> Function(String) _refreshAndRead;
  final WriteEncoding Function() _encoding;
  final Future<void> Function(WriteEncoding) _rememberEncoding;
  final void Function() _disableWrites;
  final Duration timeout;

  /// Insertion-ordered: the oldest queued parameter goes first.
  final _queue = <String, _Job>{};
  var _busy = false;
  var _disabled = false;

  bool get busy => _busy || _queue.isNotEmpty;

  Future<WriteOutcome> write(CameraParam param, String value) {
    if (_disabled) return Future.value(const WritesDisabled());
    final queued = _queue[param.wireKey];
    if (queued != null) {
      queued.completer.complete(const WriteSuperseded());
      _queue.remove(param.wireKey);
    }
    final job = _Job(param, value);
    _queue[param.wireKey] = job;
    unawaited(_pump());
    return job.completer.future;
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    try {
      while (_queue.isNotEmpty) {
        final key = _queue.keys.first;
        final job = _queue.remove(key)!;
        if (_disabled) {
          job.completer.complete(const WritesDisabled());
          continue;
        }
        await _run(job);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _run(_Job job) async {
    final timer = Timer(timeout, () {
      if (!job.completer.isCompleted) {
        job.completer.complete(const WriteTimedOut());
      }
    });
    final outcome = await _attempt(job);
    timer.cancel();
    if (!job.completer.isCompleted) job.completer.complete(outcome);
  }

  Future<WriteOutcome> _attempt(_Job job) async {
    final key = job.param.wireKey;
    final values = {key: job.value};
    Map<String, Object?>? response;
    try {
      final known = _encoding();
      if (known != WriteEncoding.unknown) {
        response = await _send(job.param.endpoint, values, known);
      } else {
        for (final candidate in _fallbackOrder) {
          try {
            response = await _send(job.param.endpoint, values, candidate);
            await _rememberEncoding(candidate);
            break;
          } on CameraApiException {
            continue;
          }
        }
        if (response == null) {
          _disabled = true;
          _disableWrites();
          return const WritesDisabled();
        }
      }
    } on CameraApiException catch (error) {
      return WriteRejected(error.cameraCode ?? error.code, error.cameraMessage);
    } on Exception {
      return const WriteRejected('transport');
    }

    final echoed = response[key];
    String? actual;
    if (echoed is String || echoed is num || echoed is bool) {
      actual = '$echoed';
    } else {
      try {
        actual = await _refreshAndRead(key);
      } on Exception {
        actual = null;
      }
    }
    if (actual == null) return const WriteTimedOut();
    return actual == job.value
        ? WriteConfirmed(actual)
        : WriteCorrected(actual);
  }
}
