import '../../darkroom/model/photo_edits.dart';

class GpuRenderDescriptor {
  const GpuRenderDescriptor(
      {required this.edits,
      required this.width,
      required this.height,
      this.lutKey = '',
      this.strength = 1});
  final PhotoEdits edits;
  final int width, height;
  final String lutKey;
  final double strength;
}
