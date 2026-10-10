import 'dart:math' as math;

/// Numeric readings of camera exposure strings, used only by programs.
///
/// Formats are firmware-derived / hardware-unverified; the UI always shows
/// the raw string.
double? parseTvSeconds(String value) {
  var text = value.trim();
  if (text.endsWith('"') || text.endsWith('s')) {
    text = text.substring(0, text.length - 1).trim();
  }
  final fraction = RegExp(r'^(\d+)/(\d+(?:\.\d+)?)$').firstMatch(text);
  if (fraction != null) {
    final numerator = double.parse(fraction.group(1)!);
    final denominator = double.parse(fraction.group(2)!);
    return denominator == 0 ? null : numerator / denominator;
  }
  final seconds = double.tryParse(text);
  return seconds != null && seconds > 0 ? seconds : null;
}

int? parseIso(String value) {
  final iso = int.tryParse(value.trim());
  return iso != null && iso > 0 ? iso : null;
}

double? parseEv(String value) {
  final text = value.trim();
  final fraction = RegExp(r'^([+-]?)(\d+)/(\d+)$').firstMatch(text);
  if (fraction != null) {
    final magnitude =
        double.parse(fraction.group(2)!) / double.parse(fraction.group(3)!);
    return fraction.group(1) == '-' ? -magnitude : magnitude;
  }
  return double.tryParse(text.startsWith('+') ? text.substring(1) : text);
}

double log2(double x) => math.log(x) / math.ln2;

/// Returns the option whose `log2(parse(option))` is closest to [target].
///
/// Options that do not parse, or exceed [max], are skipped.
String? nearestByLog(
  List<String> options,
  double target,
  num? Function(String) parse, {
  double? max,
}) {
  String? best;
  var bestDistance = double.infinity;
  for (final option in options) {
    final value = parse(option)?.toDouble();
    if (value == null || value <= 0) continue;
    if (max != null && value > max * 1.0001) continue;
    final distance = (log2(value) - target).abs();
    if (distance < bestDistance) {
      best = option;
      bestDistance = distance;
    }
  }
  return best;
}

/// True when every option parses, except the ones in [allow].
bool allParse(
  List<String> options,
  Object? Function(String) parse, {
  Set<String> allow = const {},
}) =>
    options.isNotEmpty &&
    options.every((o) => allow.contains(o) || parse(o) != null);
