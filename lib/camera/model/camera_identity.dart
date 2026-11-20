class CameraIdentity {
  const CameraIdentity({required this.model, required this.firmware});

  final String model;
  final String firmware;

  static const supportedModels = [
    'RICOH GR III',
    'RICOH GR IIIx',
    'RICOH GR IV',
    'RICOH GR IV Monochrome',
    'RICOH GR III HDF',
    'RICOH GR IIIx HDF',
    'RICOH GR IV HDF',
  ];

  bool get isSupportedModel => supportedModels.contains(model.trim());

  String get companionModel => model
      .trim()
      .replaceFirst(RegExp(r'^RICOH '), '')
      .replaceFirst(RegExp(r' HDF$'), '');

  bool get supportsM10v =>
      isSupportedModel && const ['GR III', 'GR IIIx'].contains(companionModel);

  bool get isVerifiedFirmware =>
      model.trim() == 'RICOH GR III' &&
      RegExp(r'^2\.10(?:\.|$)').hasMatch(firmware.trim());

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
