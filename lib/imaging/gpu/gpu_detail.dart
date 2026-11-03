import 'dart:ui';

/// A one-off full-source detail patch. The normalized rectangle belongs to the
/// photo, not to the editor viewport or decorative frame canvas.
class GpuDetail {
  const GpuDetail(this.path, this.region);
  final String path;
  final Rect region;
}
