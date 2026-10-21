import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../imaging/imaging_engine.dart';
import 'workbench_style.dart';

class ComparisonPreview extends StatefulWidget {
  const ComparisonPreview(
      {super.key, this.original, this.effect, required this.effectName});
  final PreviewImage? original, effect;
  final String effectName;
  @override
  State<ComparisonPreview> createState() => _ComparisonPreviewState();
}

class _ComparisonPreviewState extends State<ComparisonPreview> {
  double _split = .5;
  ui.Image? _original, _effect;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(covariant ComparisonPreview old) {
    super.didUpdateWidget(old);
    if (old.original != widget.original || old.effect != widget.effect) {
      _update();
    }
  }

  Future<ui.Image?> _image(PreviewImage? pixels) async {
    if (pixels == null) return null;
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels.rgba, pixels.width, pixels.height,
        ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  Future<void> _update() async {
    final generation = ++_generation;
    final original = await _image(widget.original),
        effect = await _image(widget.effect);
    if (!mounted || generation != _generation) {
      original?.dispose();
      effect?.dispose();
      return;
    }
    setState(() {
      _original?.dispose();
      _effect?.dispose();
      _original = original;
      _effect = effect;
    });
  }

  @override
  void dispose() {
    _generation++;
    _original?.dispose();
    _effect?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
      aspectRatio: 3 / 2,
      child: LayoutBuilder(
          builder: (context, bounds) => Semantics(
                label: '原色与${widget.effectName}对比',
                value: '原色 ${(_split * 100).round()}%',
                increasedValue:
                    '原色 ${((_split + .1).clamp(0, 1) * 100).round()}%',
                decreasedValue:
                    '原色 ${((_split - .1).clamp(0, 1) * 100).round()}%',
                slider: true,
                onIncrease: () =>
                    setState(() => _split = (_split + .1).clamp(0, 1)),
                onDecrease: () =>
                    setState(() => _split = (_split - .1).clamp(0, 1)),
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (event) => setState(() => _split =
                        (_split + event.delta.dx / bounds.maxWidth)
                            .clamp(0, 1)),
                    child: Stack(fit: StackFit.expand, children: [
                      _photo(_effect ?? _original),
                      ClipRect(
                          clipper: _SplitClipper(_split),
                          child: _photo(_original)),
                      Positioned(left: 12, top: 12, child: _label('原色')),
                      Positioned(
                          right: 12, top: 12, child: _label(widget.effectName)),
                      Positioned(
                          left: bounds.maxWidth * _split - .5,
                          top: 0,
                          bottom: 0,
                          width: 1,
                          child: const ColoredBox(color: workbenchCream)),
                      Positioned(
                          left: (bounds.maxWidth * _split - 22)
                              .clamp(0, bounds.maxWidth - 44),
                          top: (bounds.maxHeight - 44) / 2,
                          width: 44,
                          height: 44,
                          child: Container(
                              decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: workbenchCream),
                              child: const RotatedBox(
                                  quarterTurns: 1,
                                  child: RotatedBox(
                                      quarterTurns: 1,
                                      child: Icon(Icons.unfold_more_rounded,
                                          color: workbenchBackground,
                                          size: 25))))),
                    ])),
              )));
  Widget _photo(ui.Image? image) => image == null
      ? Image.asset('assets/images/film_workbench_sample.jpg',
          fit: BoxFit.cover, cacheWidth: 960)
      : RawImage(
          image: image, fit: BoxFit.cover, filterQuality: FilterQuality.low);
  Widget _label(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: Colors.black54, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: const TextStyle(fontSize: 10, color: workbenchCream)));
}

class _SplitClipper extends CustomClipper<Rect> {
  const _SplitClipper(this.split);
  final double split;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * split, size.height);
  @override
  bool shouldReclip(_SplitClipper old) => old.split != split;
}
