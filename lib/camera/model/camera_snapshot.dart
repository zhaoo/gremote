import 'camera_identity.dart';

class CameraBattery {
  const CameraBattery({required this.level, required this.acPowered});

  final int level;
  final bool acPowered;

  @override
  bool operator ==(Object other) =>
      other is CameraBattery &&
      other.level == level &&
      other.acPowered == acPowered;

  @override
  int get hashCode => Object.hash(level, acPowered);

  @override
  String toString() => 'CameraBattery(level: $level, acPowered: $acPowered)';
}

class CameraSnapshot {
  const CameraSnapshot({required this.identity, required this.battery});

  final CameraIdentity identity;
  final CameraBattery battery;
}
