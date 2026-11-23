import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'diagnostic_event.dart';
import 'diagnostic_redactor.dart';
import '../platform/app_package_info.dart';

final diagnosticStoreProvider = Provider<DiagnosticStore>((_) {
  final store =
      DiagnosticStore(persistence: const AppFileDiagnosticPersistence());
  unawaited(AppPackageInfo.fromPlatform().then<void>((info) {
    store.setAppIdentity(version: info.version, buildNumber: info.buildNumber);
  }, onError: (Object _, StackTrace __) {
    // Diagnostics remain usable when a host has no app-info bridge.
  }));
  return store;
});

abstract interface class DiagnosticPersistence {
  Future<void> write(String json);
}

class DiagnosticStore {
  DiagnosticStore({required DiagnosticPersistence persistence})
      : _persistence = persistence;

  static const maxMemoryEvents = 2000;
  static const maxPersistedEvents = 500;

  final DiagnosticPersistence _persistence;
  final ListQueue<DiagnosticEvent> _events = ListQueue();
  Map<String, String>? _appIdentity;

  void setAppIdentity({required String version, required String buildNumber}) {
    _appIdentity = {'version': version, 'buildNumber': buildNumber};
  }

  int get length => _events.length;

  void record(DiagnosticEvent event) {
    _events.addLast(event);
    while (_events.length > maxMemoryEvents) {
      _events.removeFirst();
    }
  }

  String exportJson() => jsonEncode(_payload(_events));

  /// Keeps the last request boundaries within chat and clipboard size limits.
  String exportRecentJson() {
    final events = _events.toList(growable: false);
    final recent = <DiagnosticEvent>[];
    for (final event in events.reversed) {
      final candidate = [event, ...recent];
      if (jsonEncode(_payload(candidate)).length > 3800) break;
      recent.insert(0, event);
    }
    return jsonEncode(_payload(recent));
  }

  Future<void> persist() {
    final skip = (_events.length - maxPersistedEvents).clamp(0, _events.length);
    return _persistence.write(jsonEncode(_payload(_events.skip(skip))));
  }

  Map<String, Object?> _payload(Iterable<DiagnosticEvent> events) => {
        'schema': 'gremote-diagnostics/1',
        if (_appIdentity != null) 'app': _appIdentity,
        'events': events.map(DiagnosticRedactor.redact).toList(growable: false),
      };
}

class AppFileDiagnosticPersistence implements DiagnosticPersistence {
  const AppFileDiagnosticPersistence();

  @override
  Future<void> write(String json) async {
    final directory = await getApplicationSupportDirectory();
    final target = File('${directory.path}/gremote-diagnostics.json');
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(json, flush: true);
    await temporary.rename(target.path);
  }
}
