// Regenerates assets/luts/*.cube from lib/darkroom/lut/builtin_looks.dart.
//
// Usage: dart run tool/generate_luts.dart
import 'dart:io';

import 'package:gremote/darkroom/lut/builtin_looks.dart';

void main() {
  Directory('assets/luts').createSync(recursive: true);
  for (final look in builtinLooks) {
    File(look.assetPath).writeAsStringSync(look.toCube());
    stdout.writeln('wrote ${look.assetPath}');
  }
}
