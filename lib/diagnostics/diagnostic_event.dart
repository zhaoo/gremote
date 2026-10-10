class DiagnosticEvent {
  const DiagnosticEvent({
    required this.stage,
    required this.monotonicMicros,
    required this.durationMs,
    required this.retryCount,
    this.firmware,
    this.statusCode,
    this.endpointPath,
    this.exceptionCode,
    this.ssid,
    this.passphrase,
    this.deviceAddress,
    this.serialNumber,
    this.filePath,
    this.latitude,
    this.longitude,
    this.httpBody,
  });

  final String stage;
  final int monotonicMicros;
  final int durationMs;
  final int retryCount;
  final String? firmware;
  final int? statusCode;
  final String? endpointPath;
  final String? exceptionCode;
  final String? ssid;
  final String? passphrase;
  final String? deviceAddress;
  final String? serialNumber;
  final String? filePath;
  final double? latitude;
  final double? longitude;
  final String? httpBody;

  @override
  String toString() => 'DiagnosticEvent('
      'stage: $stage, monotonicMicros: $monotonicMicros, '
      'durationMs: $durationMs, retryCount: $retryCount, '
      'firmware: $firmware, statusCode: $statusCode, '
      'endpointPath: ${endpointPath?.split('?').first}, '
      'exceptionCode: $exceptionCode, sensitiveFields: <redacted>)';
}
