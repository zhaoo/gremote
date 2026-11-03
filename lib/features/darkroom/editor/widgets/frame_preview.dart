import 'dart:ui' as ui;
import 'dart:io';
import '../../../../imaging/gpu/gpu_detail.dart';

import 'package:flutter/material.dart';

import '../../../../darkroom/frame/frame_layout.dart';
import '../../../../darkroom/frame/frame_painter.dart';
import '../../../../imaging/imaging_engine.dart';

/// Draws [layout] scaled to the available width, with [image] in the photo
/// rectangle; uses the same [FramePainter] as the export rasterizer.
class FramePreview extends StatefulWidget {
  const FramePreview(
      {required this.layout,
      this.image,
      this.textureId,
      this.detail,
      super.key});

  final FrameLayout layout;
  final PreviewImage? image;
  final int? textureId;
  final GpuDetail? detail;

  @override
  State<FramePreview> createState() => _FramePreviewState();
}

class _FramePreviewState extends State<FramePreview> {
  ui.Image? _image;
  PreviewImage? _source;

  @override
  void initState() {
    super.initState();
    _convert();
  }

  @override
  void didUpdateWidget(FramePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != _source) _convert();
    if (oldWidget.detail != widget.detail && oldWidget.detail != null) {
      FileImage(File(oldWidget.detail!.path)).evict();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _convert() {
    final source = _source = widget.image;
    if (source == null) return;
    ui.decodeImageFromPixels(
      source.rgba,
      source.width,
      source.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (!mounted || _source != source) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    return Center(
      child: AspectRatio(
        aspectRatio: layout.canvasWidth / layout.canvasHeight,
        child: widget.textureId == null
            ? CustomPaint(painter: _FramePainter(layout, _image))
            : LayoutBuilder(builder: (context, constraints) {
                final scale = constraints.maxWidth / layout.canvasWidth,
                    p = layout.photo;
                return Stack(fit: StackFit.expand, children: [
                  CustomPaint(
                      painter: _FramePainter(layout, null, overlays: false)),
                  Positioned(
                      left: p.x * scale,
                      top: p.y * scale,
                      width: p.width * scale,
                      height: p.height * scale,
                      child: Texture(
                          textureId: widget.textureId!,
                          filterQuality: FilterQuality.medium)),
                  if (widget.detail case final detail?)
                    Positioned(
                        left: (p.x + detail.region.left * p.width) * scale,
                        top: (p.y + detail.region.top * p.height) * scale,
                        width: detail.region.width * p.width * scale,
                        height: detail.region.height * p.height * scale,
                        child: Image.file(File(detail.path),
                            key: ValueKey(detail.path),
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.high)),
                  IgnorePointer(
                      child: CustomPaint(
                          painter:
                              _FramePainter(layout, null, background: false))),
                ]);
              }),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.layout, this.image,
      {this.background = true, this.overlays = true});
  final bool background, overlays;

  final FrameLayout layout;
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / layout.canvasWidth;
    if (background) {
      canvas.drawRect(
          Offset.zero & size, Paint()..color = Color(layout.background));
    }
    final p = layout.photo;
    final photoRect = Rect.fromLTWH(
        p.x * scale, p.y * scale, p.width * scale, p.height * scale);
    final image = this.image;
    if (!background) {
      // Foreground-only pass keeps frame lettering over the platform texture.
    } else if (image == null) {
      canvas.drawRect(photoRect, Paint()..color = const Color(0xFF2A2C2A));
    } else {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        photoRect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    if (overlays)
      for (final overlay in layout.overlays) {
        final r = overlay.rect;
        canvas
          ..save()
          ..translate(r.x * scale, r.y * scale)
          ..clipRect(Rect.fromLTWH(0, 0, r.width * scale, r.height * scale));
        FramePainter.paintOverlay(canvas, overlay, scale: scale);
        canvas.restore();
      }
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.layout != layout ||
      old.image != image ||
      old.background != background ||
      old.overlays != overlays;
}
