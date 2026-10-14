import 'dart:async';
import 'dart:collection';

/// Camera HTTP bandwidth is shared: drain previews before saving originals.
class CameraTransferGate {
  final _waiting = Queue<void Function()>();
  int _active = 0;
  int _generation = 0;
  bool _saving = false;
  Completer<void>? _drained;
  Completer<void>? _released;

  Future<T> thumbnail<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    final generation = _generation;
    _waiting.add(() {
      _active++;
      Future.sync(() {
        if (generation != _generation) {
          throw StateError('Camera session changed');
        }
        return operation();
      }).then(result.complete, onError: result.completeError).whenComplete(() {
        _active--;
        if (_active == 0) {
          _drained?.complete();
          _drained = null;
        }
        _pump();
      });
    });
    _pump();
    return result.future;
  }

  Future<T> originals<T>(Future<T> Function() operation) async {
    while (_saving) {
      await _released!.future;
    }
    _saving = true;
    _released = Completer<void>();
    try {
      if (_active > 0) {
        _drained = Completer<void>();
        await _drained!.future;
      }
      return await operation();
    } finally {
      _saving = false;
      _released!.complete();
      _pump();
    }
  }

  void invalidate() {
    _generation++;
  }

  void _pump() {
    while (!_saving && _active < 2 && _waiting.isNotEmpty) {
      _waiting.removeFirst()();
    }
  }
}
