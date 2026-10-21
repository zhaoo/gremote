import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../imaging/imaging_engine.dart';
import '../../imaging/imaging_exception.dart';
import '../model/film_recipe.dart';
import 'film_preview_engine.dart';

class _PreviewJob {
  const _PreviewJob(this.source, this.recipe, this.generation);
  final PreviewImage source;
  final FilmRecipe recipe;
  final int generation;
}

class FilmPreviewController extends ChangeNotifier {
  FilmPreviewController(this.engine);
  static const cacheBudget = 48 * 1024 * 1024;
  final FilmPreviewEngine engine;
  FilmPreviewResult? result;
  Future<void> _running = Future.value();
  Future<void> get whenIdle async {
    while (busy) {
      await _running;
    }
  }

  Object? error;
  _PreviewJob? _pending, _active;
  ImagingCancelToken? _cancel;
  bool _disposed = false;
  int _generation = 0, _maxEdge = 960;
  bool get busy => _active != null || _pending != null;
  int get generation => _generation;
  int get retainedBytes =>
      (_pending?.source.rgba.length ?? 0) +
      (_active?.source.rgba.length ?? 0) +
      (result?.image.rgba.length ?? 0);

  void request(
      {required PreviewImage source,
      required FilmRecipe recipe,
      bool alreadyProcessed = false}) {
    if (_disposed) return;
    _generation++;
    _cancel?.cancel();
    error = null;
    if (source.rgba.length * 6 > cacheBudget) {
      error = const ImagingException(ImagingErrorCode.tooLarge);
      _pending = null;
      notifyListeners();
      return;
    }
    if (alreadyProcessed) {
      _pending = null;
      result = FilmPreviewResult(
          image: source,
          recipeFingerprint: recipe.fingerprint,
          generation: _generation,
          stage: PreviewStage.full,
          bypassed: true);
      notifyListeners();
      return;
    }
    _pending = _PreviewJob(source, recipe, _generation);
    _pump();
    notifyListeners();
  }

  void _pump() {
    if (_disposed || _active != null || _pending == null) return;
    final job = _active = _pending!;
    _pending = null;
    unawaited(_running = _run(job));
  }

  bool _current(_PreviewJob job) => !_disposed && job.generation == _generation;
  Future<void> _run(_PreviewJob job) async {
    final cancel = _cancel = ImagingCancelToken();
    try {
      var color = await engine.render(
          source: job.source,
          recipe: job.recipe,
          stage: PreviewStage.color,
          generation: job.generation,
          cancel: cancel,
          maxEdge: _maxEdge);
      if (!_current(job)) return;
      result = color;
      notifyListeners();
      final parameters = job.recipe.parameters;
      final spatial = (parameters['grain'] ?? 0) > 0 ||
          (parameters['haloGain'] ?? 0) > 0 ||
          (parameters['leakGain'] ?? 0) > 0;
      if (spatial) {
        color = await engine.render(
            source: job.source,
            recipe: job.recipe,
            stage: PreviewStage.full,
            generation: job.generation,
            cancel: cancel,
            maxEdge: _maxEdge);
      } else {
        color = FilmPreviewResult(
            image: color.image,
            recipeFingerprint: color.recipeFingerprint,
            generation: color.generation,
            stage: PreviewStage.full);
      }
      if (_current(job)) {
        result = color;
        error = null;
      }
    } on ImagingException catch (e) {
      if (_current(job) &&
          e.code == ImagingErrorCode.outOfMemory &&
          _maxEdge > 640) {
        _maxEdge = 640;
        _pending = job;
      } else if (_current(job) && e.code != ImagingErrorCode.cancelled) {
        error = e;
      }
    } catch (e) {
      if (_current(job)) error = e;
    } finally {
      // Never free the shared cancellation flag while native code may still read it.
      cancel.dispose();
      if (identical(_cancel, cancel)) _cancel = null;
      _active = null;
      if (!_disposed) {
        notifyListeners();
        _pump();
      }
    }
  }

  void clear() {
    _generation++;
    _pending = null;
    result = null;
    _cancel?.cancel();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending = null;
    result = null;
    _cancel?.cancel();
    super.dispose();
  }
}
