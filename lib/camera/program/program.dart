import 'package:meta/meta.dart';

import '../capture/capture_tracker.dart';
import '../params/param_writer.dart';
import '../sync/camera_state.dart';

@immutable
class ProgramStep {
  const ProgramStep({this.params = const {}, this.recipeId});

  final Map<String, String> params;
  final String? recipeId;
}

@immutable
class ProgramContext {
  const ProgramContext({
    required this.state,
    required this.nudgeEv,
    required this.index,
  });

  final CameraState state;
  final double nudgeEv;
  final int index;
}

abstract interface class Program {
  String get kind;
  String get label;
  int get frameCount;
  Duration? get interval;
  bool get supportsNudge;

  /// User-readable reason, or null when this camera state can run it.
  String? refusal(CameraState state);

  Future<ProgramStep> step(ProgramContext context);
}

abstract interface class ProgramCamera {
  CameraState get state;

  Future<WriteOutcome> setParam(String wireKey, String value);

  Future<List<CaptureRecord>> shootAndAwait({
    required bool autoFocus,
    required CaptureContext context,
  });
}
