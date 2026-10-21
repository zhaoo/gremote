import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../imaging/imaging_engine.dart';
import '../../../film/model/film_recipe.dart';
import 'workbench_style.dart';

class FilmComparisonGrid extends StatelessWidget {
  const FilmComparisonGrid(
      {super.key,
      required this.original,
      required this.recipes,
      required this.images,
      required this.names,
      required this.onChoose});
  final PreviewImage? original;
  final List<FilmRecipe> recipes;
  final Map<String, PreviewImage> images;
  final List<String> names;
  final ValueChanged<int> onChoose;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: _PhotoTile(
                  key: const ValueKey('film-compare-original'),
                  image: original,
                  label: '原色')),
          const SizedBox(width: 8),
          Expanded(child: _tile(0)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _tile(1)),
          const SizedBox(width: 8),
          Expanded(child: _tile(2))
        ]),
      ]));
  Widget _tile(int index) => _PhotoTile(
      key: ValueKey('film-compare-$index'),
      image: images[recipes[index].fingerprint],
      label: names[index],
      onChoose: () => onChoose(index));
}

class _PhotoTile extends StatefulWidget {
  const _PhotoTile(
      {super.key, required this.image, required this.label, this.onChoose});
  final PreviewImage? image;
  final String label;
  final VoidCallback? onChoose;
  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  ui.Image? _image;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant _PhotoTile old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image) _decode();
  }

  Future<void> _decode() async {
    final token = ++_generation, pixels = widget.image;
    _image?.dispose();
    _image = null;
    if (pixels == null) return;
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels.rgba, pixels.width, pixels.height,
        ui.PixelFormat.rgba8888, done.complete);
    final image = await done.future;
    if (!mounted || token != _generation) {
      image.dispose();
      return;
    }
    setState(() => _image = image);
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
                aspectRatio: 3 / 2,
                child: ColoredBox(
                    color: const Color(0xff283429),
                    child: _image == null
                        ? const Center(
                            child: Text('等待画面',
                                style: TextStyle(
                                    color: workbenchMuted, fontSize: 11)))
                        : RawImage(image: _image, fit: BoxFit.cover)))),
        SizedBox(
            height: 44,
            child: widget.onChoose == null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(widget.label,
                        style: const TextStyle(
                            color: workbenchMuted, fontSize: 12)))
                : TextButton(
                    onPressed: widget.onChoose,
                    child: Row(children: [
                      Expanded(
                          child: Text(widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12))),
                      const Icon(Icons.swap_horiz, size: 16)
                    ]))),
      ]);
}
