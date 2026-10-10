import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../imaging/imaging_engine.dart';
import '../../media/local/local_media_repository.dart';
import '../darkroom_providers.dart';
import '../model/edit_document.dart';
import '../model/export_recipe.dart';
import 'export_service.dart';

enum ExportItemStatus {
  pending('等待'),
  running('导出中'),
  done('完成'),
  failed('失败'),
  cancelled('已取消');

  const ExportItemStatus(this.label);
  final String label;
}

@immutable
class ExportQueueItem {
  const ExportQueueItem({
    required this.item,
    required this.doc,
    this.status = ExportItemStatus.pending,
    this.outcome,
    this.failure,
  });

  final LocalMediaItem item;
  final EditDocument doc;
  final ExportItemStatus status;
  final ExportOutcome? outcome;
  final ExportFailure? failure;

  ExportQueueItem withStatus(
    ExportItemStatus status, {
    ExportOutcome? outcome,
    ExportFailure? failure,
  }) =>
      ExportQueueItem(
          item: item,
          doc: doc,
          status: status,
          outcome: outcome,
          failure: failure);
}

@immutable
class ExportQueueState {
  const ExportQueueState({this.items = const [], this.running = false});

  final List<ExportQueueItem> items;
  final bool running;

  int count(ExportItemStatus status) =>
      items.where((i) => i.status == status).length;
}

final exportQueueProvider =
    NotifierProvider<ExportQueueController, ExportQueueState>(
        ExportQueueController.new);

/// Exports photos one after another; a failure never stops the batch.
class ExportQueueController extends Notifier<ExportQueueState> {
  ImagingCancelToken? _token;
  bool _cancelRequested = false;

  @override
  ExportQueueState build() => const ExportQueueState();

  /// Applies [recipe] to every photo while keeping each photo's captions.
  Future<void> start(List<LocalMediaItem> items, ExportRecipe recipe) =>
      startEach([for (final item in items) (item, recipe)]);

  /// Exports each photo using the recipe paired with it.
  Future<void> startEach(List<(LocalMediaItem, ExportRecipe)> jobs) async {
    if (state.running) throw StateError('export queue is busy');
    _cancelRequested = false;
    state = const ExportQueueState(running: true);
    final store = ref.read(darkroomStoreProvider);
    final now = DateTime.now();
    state = ExportQueueState(running: true, items: [
      for (final (item, recipe) in jobs)
        ExportQueueItem(
          item: item,
          doc: (await store.loadEdit(item.id))?.copyWith(recipe: recipe) ??
              EditDocument(mediaId: item.id, recipe: recipe, updatedAt: now),
        ),
    ]);
    await _run();
  }

  Future<void> retryFailed() async {
    if (state.running) return;
    _cancelRequested = false;
    state = ExportQueueState(running: true, items: [
      for (final i in state.items)
        i.status == ExportItemStatus.failed
            ? i.withStatus(ExportItemStatus.pending)
            : i,
    ]);
    await _run();
  }

  void cancel() {
    _cancelRequested = true;
    _token?.cancel();
  }

  void clear() {
    if (!state.running) state = const ExportQueueState();
  }

  Future<void> _run() async {
    final service = ref.read(exportServiceProvider);
    for (var i = 0; i < state.items.length; i++) {
      final entry = state.items[i];
      if (entry.status != ExportItemStatus.pending) continue;
      if (_cancelRequested) {
        _update(i, entry.withStatus(ExportItemStatus.cancelled));
        continue;
      }
      _update(i, entry.withStatus(ExportItemStatus.running));
      final token = _token = ImagingCancelToken();
      try {
        final outcome =
            await service.export(entry.item, entry.doc, cancel: token);
        _update(i, entry.withStatus(ExportItemStatus.done, outcome: outcome));
      } on ExportCancelled {
        _update(i, entry.withStatus(ExportItemStatus.cancelled));
      } on ExportFailure catch (failure) {
        _update(i, entry.withStatus(ExportItemStatus.failed, failure: failure));
      } catch (error) {
        _update(
          i,
          entry.withStatus(ExportItemStatus.failed,
              failure: ExportFailure(
                  stage: ExportStage.compose,
                  fileName: entry.item.displayName,
                  code: 'unknown',
                  reason: '$error')),
        );
      } finally {
        _token = null;
        token.dispose();
      }
    }
    state = ExportQueueState(items: state.items);
  }

  void _update(int index, ExportQueueItem item) {
    state = ExportQueueState(
      items: [...state.items]..[index] = item,
      running: state.running,
    );
  }
}
