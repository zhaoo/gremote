import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../params/camera_param.dart';
import '../params/exposure_values.dart';
import '../sync/camera_state.dart';
import 'program.dart';

@immutable
class ExposurePair {
  const ExposurePair({required this.tv, required this.sv});

  final String tv;
  final String sv;
}

class PlannedRampProgram implements Program {
  PlannedRampProgram({
    required this.start,
    required this.end,
    required this.frames,
    required this.interval,
    this.maxShutterSeconds,
  }) {
    if (frames < 2) throw ArgumentError.value(frames, 'frames');
    if (interval < const Duration(seconds: 2) ||
        interval > const Duration(minutes: 10)) {
      throw ArgumentError.value(interval, 'interval');
    }
    if (maxShutterSeconds != null && maxShutterSeconds! <= 0) {
      throw ArgumentError.value(maxShutterSeconds, 'maxShutterSeconds');
    }
  }

  final ExposurePair start;
  final ExposurePair end;
  final int frames;
  @override
  final Duration interval;
  final double? maxShutterSeconds;

  @override
  String get kind => 'plannedRamp';
  @override
  String get label => '计划渐变延时';
  @override
  int get frameCount => frames;
  @override
  bool get supportsNudge => true;

  double get shutterCap {
    final byInterval = math.max(0.001, interval.inMilliseconds / 1000 - 1);
    return math.min(maxShutterSeconds ?? 30, math.min(byInterval, 30));
  }

  @override
  String? refusal(CameraState state) {
    if (state.value(ParamKey.exposureMode) != 'M') return '需要把机身拨盘切到 M 档';
    final tv = state.param(ParamKey.shutter);
    final sv = state.param(ParamKey.iso);
    if (tv?.writable != true || sv?.writable != true) return '快门或 ISO 不可写';
    if (parseTvSeconds(start.tv) == null || parseTvSeconds(end.tv) == null) {
      return '起止快门无法解析';
    }
    if (parseIso(start.sv) == null || parseIso(end.sv) == null) {
      return '起止 ISO 必须是数值';
    }
    if (!allParse(tv!.options, parseTvSeconds) ||
        !allParse(sv!.options, parseIso, allow: const {'auto'})) {
      return '相机曝光档位无法解析';
    }
    return null;
  }

  @override
  Future<ProgramStep> step(ProgramContext context) async =>
      _stepWithOffset(context, 0);

  ProgramStep _stepWithOffset(ProgramContext context, double extraEv) {
    final startTv = parseTvSeconds(start.tv)!;
    final endTv = parseTvSeconds(end.tv)!;
    final isoBase = parseIso(start.sv)!;
    final endIso = parseIso(end.sv)!;
    final startExposure = log2(startTv) + log2(isoBase / 100);
    final endExposure = log2(endTv) + log2(endIso / 100);
    final progress = context.index / (frames - 1);
    final targetExposure = startExposure +
        (endExposure - startExposure) * progress +
        context.nudgeEv +
        extraEv;

    var shutter = math.pow(2, targetExposure) / (isoBase / 100);
    var iso = isoBase.toDouble();
    if (shutter > shutterCap) {
      shutter = shutterCap;
      iso = 100 * math.pow(2, targetExposure) / shutter;
    }
    final tvOptions = context.state.param(ParamKey.shutter)!.options;
    final svOptions = context.state.param(ParamKey.iso)!.options;
    final tv = nearestByLog(
      tvOptions,
      log2(shutter),
      parseTvSeconds,
      max: shutterCap,
    );
    final sv = nearestByLog(svOptions, log2(iso), parseIso);
    if (tv == null || sv == null) return const ProgramStep();
    return ProgramStep(params: {'tv': tv, 'sv': sv});
  }
}

/// Planned ramp plus experimental Live View luminance feedback.
class MeteredRampProgram extends PlannedRampProgram {
  MeteredRampProgram({
    required super.start,
    required super.end,
    required super.frames,
    required super.interval,
    required Future<double?> Function() meter,
    super.maxShutterSeconds,
  }) : _meter = meter;

  final Future<double?> Function() _meter;
  double? _targetLuma;
  double _meterOffsetEv = 0;

  double get meterOffsetEv => _meterOffsetEv;

  @override
  String get kind => 'meteredRamp';
  @override
  String get label => '测光渐变延时（实验）';

  @override
  Future<ProgramStep> step(ProgramContext context) async {
    final current = await _meter();
    if (current != null && current > 0) {
      if (_targetLuma == null) {
        _targetLuma = current;
      } else {
        final delta = log2(_targetLuma! / current);
        if (delta.abs() >= 1 / 6) {
          _meterOffsetEv += delta.clamp(-1 / 3, 1 / 3);
        }
      }
    }
    return _stepWithOffset(context, _meterOffsetEv);
  }
}
