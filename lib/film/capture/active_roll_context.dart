import 'package:flutter_riverpod/flutter_riverpod.dart';

class FrozenRollContext {
  const FrozenRollContext({required this.rollId, required this.recipeJson});
  final String rollId, recipeJson;
}

/// UI updates this only after the roll transaction succeeds. Capture requests
/// copy its strings before awaiting camera I/O, never retain a mutable recipe.
final activeRollCaptureContextProvider =
    StateProvider<FrozenRollContext?>((_) => null);
