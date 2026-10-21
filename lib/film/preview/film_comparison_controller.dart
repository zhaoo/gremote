import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../imaging/imaging_engine.dart';
import '../model/film_recipe.dart';
import 'film_preview_engine.dart';

class _Batch {
  _Batch(this.source, this.recipes, this.generation, this.processed);
  final PreviewImage source;
  final List<FilmRecipe> recipes;
  final int generation;
  final bool processed;
}

/// Three small outputs, one native worker, one latest pending batch.
class FilmComparisonController extends ChangeNotifier {
  FilmComparisonController(this.engine);
  final FilmPreviewEngine engine;
  final images = <String, PreviewImage>{};
  _Batch? _pending, _active;
  ImagingCancelToken? _cancel;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _running = Future.value();
  Future<void> get whenIdle async {
    while (busy) {
      await _running;
    }
  }

  Object? error;
  bool get busy => _active != null || _pending != null;
  int get retainedBytes =>
      images.values.fold(0, (n, v) => n + v.rgba.length) +
      (_active?.source.rgba.length ?? 0) +
      (_pending?.source.rgba.length ?? 0);
  void clear() {
    _generation++;
    _pending = null;
    images.clear();
    _cancel?.cancel();
  }

  void request(PreviewImage source, List<FilmRecipe> recipes,
      {bool processed = false}) {
    if (_disposed) return;
    clear();
    error = null;
    if (recipes.length != 3 || source.rgba.length * 8 > 48 * 1024 * 1024) {
      error = const FormatException('对比照片过大');
      notifyListeners();
      return;
    }
    _pending =
        _Batch(source, List.unmodifiable(recipes), _generation, processed);
    _pump();
  }

  void _pump() {
    if (_disposed || _active != null || _pending == null) return;
    final batch = _active = _pending!;
    _pending = null;
    unawaited(_running = _run(batch));
  }

  Future<void> _run(_Batch batch) async {
    final token = _cancel = ImagingCancelToken();
    bool current() => !_disposed && batch.generation == _generation;
    try {
      for (final recipe in batch.recipes) {
        if (!current()) break;
        final image = batch.processed
            ? batch.source
            : (await engine.render(
                    source: batch.source,
                    recipe: recipe,
                    stage: PreviewStage.full,
                    generation: batch.generation,
                    cancel: token,
                    maxEdge: 640))
                .image;
        if (!current()) break;
        images[recipe.fingerprint] = image;
        notifyListeners();
      }
    } catch (e) {
      if (current()) error = e;
    } finally {
      token.dispose();
      if (identical(token, _cancel)) _cancel = null;
      _active = null;
      if (!_disposed) {
        notifyListeners();
        _pump();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    super.dispose();
  }
}
