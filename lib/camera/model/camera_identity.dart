class CameraIdentity {
  const CameraIdentity({required this.model, required this.firmware});

  final String model;
  final String firmware;

  bool get isSupportedModel => model.trim() == 'RICOH GR III';

  bool get isVerifiedFirmware => firmware.trim().startsWith('2.10');

  @override
  bool operator ==(Object other) =>
      other is CameraIdentity &&
      other.model == model &&
      other.firmware == firmware;

  @override
  int get hashCode => Object.hash(model, firmware);

  @override
  String toString() => 'CameraIdentity(model: $model, firmware: $firmware)';
}
