import 'dart:async';

/// One memory-intensive export across darkroom and contact sheets at a time.
class ExportWorkGate {
  static Future<void> _tail = Future.value();
  static Future<void Function()> acquire() async {
    final before = _tail;
    final release = Completer<void>();
    _tail = release.future;
    await before;
    return () {
      if (!release.isCompleted) release.complete();
    };
  }
}
