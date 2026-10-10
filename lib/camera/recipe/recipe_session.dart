import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../capture/capture_tracker.dart';
import '../connection/connection_controller.dart';
import '../connection/connection_state.dart';
import '../params/camera_param.dart';
import '../params/param_writer.dart';
import '../sync/camera_state.dart';
import '../sync/camera_state_controller.dart';
import 'combo_recipe.dart';
import 'recipe_store.dart';

@immutable
class RecipeSessionState {
  const RecipeSessionState({
    required this.active,
    this.detached = false,
    this.switching = false,
  });

  factory RecipeSessionState.factory() =>
      RecipeSessionState(active: ComboRecipe.factory);

  final ComboRecipe active;
  final bool detached;
  final bool switching;

  RecipeSessionState copyWith({
    ComboRecipe? active,
    bool? detached,
    bool? switching,
  }) =>
      RecipeSessionState(
        active: active ?? this.active,
        detached: detached ?? this.detached,
        switching: switching ?? this.switching,
      );
}

final recipeSessionProvider =
    NotifierProvider<RecipeSession, RecipeSessionState>(RecipeSession.new);

/// Couples a selected combo recipe to the camera effect and tags captures.
class RecipeSession extends Notifier<RecipeSessionState> {
  StreamSubscription<CaptureRecord>? _captures;

  @override
  RecipeSessionState build() {
    ref.listen(cameraStateControllerProvider, (_, camera) => _onCamera(camera));
    ref.listen(connectionControllerProvider, (_, connection) {
      if (connection is! ConnectionReady) {
        state = RecipeSessionState.factory();
      }
    });
    _captures = ref
        .read(cameraStateControllerProvider.notifier)
        .captures
        .listen(_onCapture);
    ref.onDispose(() => unawaited(_captures?.cancel()));
    return RecipeSessionState.factory();
  }

  /// Returns null when no camera write was needed.
  Future<WriteOutcome?> activate(ComboRecipe recipe) async {
    if (recipe.isFactory || recipe.effect == null) {
      state = RecipeSessionState(active: recipe);
      return null;
    }
    state = state.copyWith(switching: true);
    final outcome = await ref
        .read(cameraStateControllerProvider.notifier)
        .setParam(ParamKey.effect.wireKey, recipe.effect!);
    if (outcome is WriteConfirmed) {
      state = RecipeSessionState(active: recipe);
    } else {
      state = state.copyWith(switching: false);
    }
    return outcome;
  }

  void _onCamera(CameraState camera) {
    final effect = state.active.effect;
    if (state.active.isFactory || effect == null) return;
    final actual = camera.value(ParamKey.effect);
    if (actual == null) return;
    final detached = actual != effect;
    if (detached != state.detached || state.switching) {
      state = state.copyWith(detached: detached, switching: false);
    }
  }

  void _onCapture(CaptureRecord record) {
    final explicit = record.recipeId;
    final recipeId = explicit ??
        (!state.active.isFactory && !state.detached ? state.active.id : null);
    if (recipeId == null) return;
    unawaited(ref.read(recipeStoreProvider).addTag(record, recipeId));
  }
}
