import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

Rect liveViewImageRect(Size viewport, Size image) {
  final fitted = applyBoxFit(BoxFit.contain, image, viewport);
  return Alignment.center.inscribe(fitted.destination, Offset.zero & viewport);
}

Offset? liveViewFocusPoint(Offset point, Rect rect) {
  if (rect.isEmpty ||
      point.dx < rect.left ||
      point.dx > rect.right ||
      point.dy < rect.top ||
      point.dy > rect.bottom) return null;
  return Offset(
      (point.dx - rect.left) / rect.width, (point.dy - rect.top) / rect.height);
}

class ShootViewfinder extends StatefulWidget {
  const ShootViewfinder(
      {required this.frame,
      required this.connected,
      required this.onConnect,
      this.onFocus,
      this.focusPoint,
      this.focusing = false,
      this.focusFailed = false,
      this.overlay = const SizedBox.shrink(),
      super.key});

  final Uint8List? frame;
  final bool connected;
  final VoidCallback onConnect;
  final ValueChanged<Offset>? onFocus;
  final Offset? focusPoint;
  final bool focusing;
  final bool focusFailed;
  final Widget overlay;

  @override
  State<ShootViewfinder> createState() => _ShootViewfinderState();
}

class _ShootViewfinderState extends State<ShootViewfinder> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _image;
  Offset? _point;
  Offset? _lastRequestedPoint;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ShootViewfinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.connected) _point = null;
    if (widget.focusPoint != _lastRequestedPoint ||
        (widget.focusing && !oldWidget.focusing)) {
      _lastRequestedPoint = widget.focusPoint;
      _point = widget.focusPoint;
    }
    if (!identical(oldWidget.frame, widget.frame)) _resolve();
  }

  void _resolve() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    if (widget.frame == null) {
      _image?.dispose();
      _image = null;
      _point = null;
      return;
    }
    final stream = MemoryImage(widget.frame!)
        .resolve(createLocalImageConfiguration(context));
    _stream = stream;
    _listener = ImageStreamListener((info, synchronous) {
      if (!mounted || !identical(stream, _stream)) {
        info.dispose();
        return;
      }
      void update() {
        final old = _image;
        if (old != null &&
            old.image.width * info.image.height !=
                info.image.width * old.image.height) _point = null;
        _image = info;
        old?.dispose();
      }

      if (synchronous) {
        update();
      } else {
        setState(update);
      }
    }, onError: (Object error, StackTrace? stack) {
      if (mounted && identical(stream, _stream)) {
        setState(() {
          _image?.dispose();
          _image = null;
          _point = null;
        });
      }
    });
    stream.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final image = _image?.image;
        final rect = image == null
            ? null
            : liveViewImageRect(constraints.biggest,
                Size(image.width.toDouble(), image.height.toDouble()));
        final point = _point;
        return ColoredBox(
            color: Colors.black,
            child: Stack(fit: StackFit.expand, children: [
              GestureDetector(
                key: const Key('live-view-focus-surface'),
                behavior: HitTestBehavior.opaque,
                onTapUp:
                    widget.connected && widget.onFocus != null && rect != null
                        ? (details) {
                            final point =
                                liveViewFocusPoint(details.localPosition, rect);
                            if (point != null) widget.onFocus!(point);
                          }
                        : null,
                child: image == null
                    ? const Center(
                        child: Text('连接相机后显示取景画面',
                            style: TextStyle(
                                color: GRemoteColors.muted, fontSize: 12)))
                    : RawImage(
                        image: image,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.low),
              ),
              if (point != null && rect != null && widget.connected)
                Positioned(
                  left: rect.left + point.dx * rect.width - 17,
                  top: rect.top + point.dy * rect.height - 17,
                  child: IgnorePointer(
                      child: SizedBox(
                          key: const Key('focus-request-box'),
                          width: 34,
                          height: 34,
                          child: DecoratedBox(
                              decoration: BoxDecoration(
                                  border: Border.all(
                                      color: widget.focusing
                                          ? const Color(0x99FFFFFF)
                                          : widget.focusFailed
                                              ? Colors.red
                                              : GRemoteColors.gold,
                                      width: 1.2))))),
                ),
              if (!widget.connected)
                Positioned(
                    right: 12,
                    bottom: 12,
                    child: TextButton(
                        onPressed: widget.onConnect,
                        child: const Text('前往连接',
                            style: TextStyle(color: GRemoteColors.gold)))),
              widget.overlay,
            ]));
      });
}
