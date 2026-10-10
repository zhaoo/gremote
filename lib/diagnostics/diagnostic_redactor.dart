import 'diagnostic_event.dart';

abstract final class DiagnosticRedactor {
  static Map<String, Object?> redact(DiagnosticEvent event) => {
        'stage': event.stage,
        'monotonicMicros': event.monotonicMicros,
        'durationMs': event.durationMs,
        if (event.firmware != null) 'firmware': event.firmware,
        if (event.statusCode != null) 'statusCode': event.statusCode,
        if (event.endpointPath != null)
          'endpointPath': _endpointPath(event.endpointPath!),
        if (event.exceptionCode != null) 'exceptionCode': event.exceptionCode,
        'retryCount': event.retryCount,
        if (event.ssid != null) 'ssid': '<redacted:ssid>',
        if (event.passphrase != null) 'passphrase': '<redacted:passphrase>',
        if (event.deviceAddress != null)
          'deviceAddress': '<redacted:device-address>',
        if (event.serialNumber != null)
          'serialNumber': '<redacted:serial-number>',
        if (event.filePath != null) 'filePath': '<redacted:file-path>',
        if (event.latitude != null || event.longitude != null)
          'location': '<redacted:gps>',
        if (event.httpBody != null) 'httpBody': '<redacted:http-body>',
      };

  static String _endpointPath(String value) {
    final parsed = Uri.tryParse(value);
    if (parsed == null || parsed.path.isEmpty) return '<redacted:endpoint>';
    return parsed.path;
  }
}
