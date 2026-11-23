import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../app/theme/app_palette.dart';
import 'live_gallery_page.dart';

/// Read-only preview shared by remote originals and saved roll photos.
class PhotoPreviewSurface extends StatelessWidget {
  const PhotoPreviewSurface(
      {super.key, required this.bytes, this.raw = false, this.loading = false});
  final Uint8List? bytes;
  final bool raw, loading;
  @override
  Widget build(BuildContext context) {
    Widget unavailable() => Center(
        child: Icon(raw ? Icons.raw_on_outlined : Icons.photo_outlined,
            size: 40, color: context.palette.muted));
    return Stack(fit: StackFit.expand, children: [
      if (bytes != null)
        InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
                child: Image.memory(bytes!,
                    fit: BoxFit.contain,
                    cacheWidth: 2048,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => unavailable())))
      else if (loading)
        const Center(child: CircularProgressIndicator())
      else
        unavailable(),
      if (raw) const Positioned(top: 16, left: 20, child: AlbumTag('RAW')),
    ]);
  }
}
