import 'dart:typed_data';

import '../../camera/recipe/shooting_recipe.dart' show exposureRecipeCrc;

const localCameraRollDirectory = 'local-import';

/// A frame written by the camera into the original JPG or DNG.
class CameraRollFrame {
  const CameraRollFrame._(this.rollId, this.number, this.targetCount);

  final String rollId;
  final int number, targetCount;

  static final _format = RegExp(r'^4d313052[0-9a-f]{56}$');

  static CameraRollFrame? parse(String? value) {
    if (value == null || !_format.hasMatch(value)) return null;
    final rollId = value.substring(8, 40);
    if (rollId == '0' * 32) return null;
    final bytes = Uint8List.fromList([
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ]);
    final data = ByteData.sublistView(bytes);
    final number = data.getUint32(20, Endian.little);
    final target = data.getUint32(24, Endian.little);
    if (target < 1 || target > 999 || number < 1 || number > target) {
      return null;
    }
    if (data.getUint32(28, Endian.little) != exposureRecipeCrc(bytes, 28)) {
      return null;
    }
    return CameraRollFrame._(rollId, number, target);
  }
}
