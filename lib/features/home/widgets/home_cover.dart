import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../home_cover_providers.dart';
import '../home_cover_manager.dart';
export '../home_cover_providers.dart' show CoverFrame;

class HomeCover extends ConsumerStatefulWidget {
  const HomeCover({super.key});
  @override
  ConsumerState<HomeCover> createState() => _HomeCoverState();
}

class _HomeCoverState extends ConsumerState<HomeCover>
    with WidgetsBindingObserver {
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    if (foreground) ref.invalidate(homeCoverDataProvider);
    setState(() => _foreground = foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_foreground) return const DefaultHomeCover();
    final data = ref.watch(homeCoverDataProvider);
    return data.when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        loading: () => const DefaultHomeCover(),
        error: (_, __) => const DefaultHomeCover(),
        data: (value) => CoverCarousel(
            frames: value.frames,
            autoplay: value.settings.autoplay,
            onManage: () async {
              await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => HomeCoverManager(data: value));
            }));
  }
}

class CoverCarousel extends StatefulWidget {
  const CoverCarousel(
      {required this.frames,
      required this.autoplay,
      required this.onManage,
      this.visible = true,
      super.key});
  final List<CoverFrame> frames;
  final bool autoplay, visible;
  final Future<void> Function() onManage;
  @override
  State<CoverCarousel> createState() => _CoverCarouselState();
}

class _CoverCarouselState extends State<CoverCarousel>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _index = 0, _pointers = 0;
  bool _foreground = true, _managing = false;
  double _drag = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(CoverCarousel old) {
    super.didUpdateWidget(old);
    if (!identical(old.frames, widget.frames)) _index = 0;
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations == true;
  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!mounted ||
        !widget.visible ||
        !_foreground ||
        _managing ||
        _pointers > 0 ||
        !widget.autoplay ||
        widget.frames.length < 2 ||
        _reduceMotion ||
        !TickerMode.of(context)) return;
    _timer = Timer(const Duration(seconds: 8), () => _move(1));
  }

  void _move(int delta) {
    if (widget.frames.isEmpty) return;
    setState(() => _index = (_index + delta) % widget.frames.length);
    _schedule();
  }

  Future<void> _manage() async {
    _managing = true;
    _schedule();
    try {
      await widget.onManage();
    } finally {
      if (mounted) {
        _managing = false;
        _schedule();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.frames.isEmpty ? null : widget.frames[_index];
    return Listener(
        onPointerDown: (_) {
          _pointers++;
          _schedule();
        },
        onPointerUp: (_) {
          _pointers = (_pointers - 1).clamp(0, 99);
          _schedule();
        },
        onPointerCancel: (_) {
          _pointers = 0;
          _schedule();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: _manage,
          onHorizontalDragStart: (_) => _drag = 0,
          onHorizontalDragUpdate: (d) => _drag += d.delta.dx,
          onHorizontalDragEnd: (_) {
            if (_drag.abs() > 24) _move(_drag < 0 ? 1 : -1);
          },
          child: Semantics(
              label: '作品封面',
              onLongPress: _manage,
              child: Stack(children: [
                AnimatedSwitcher(
                    duration: _reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    child: frame == null
                        ? const DefaultHomeCover()
                        : SizedBox(
                            key: ValueKey(
                                '${frame.entry.uri}:${frame.entry.id}'),
                            height: 232,
                            width: double.infinity,
                            child: Image.memory(frame.bytes,
                                fit: BoxFit.cover,
                                alignment:
                                    Alignment(frame.entry.x, frame.entry.y),
                                gaplessPlayback: false,
                                excludeFromSemantics: true,
                                errorBuilder: (_, __, ___) =>
                                    const DefaultHomeCover()))),
                if (widget.frames.length > 1)
                  Positioned(
                      bottom: 12,
                      right: 20,
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              color: const Color(0x88000000),
                              borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              child: Text(
                                  '${_index + 1} / ${widget.frames.length}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white))))),
              ])),
        ));
  }
}

class DefaultHomeCover extends StatelessWidget {
  const DefaultHomeCover({super.key});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.5);
    return SizedBox(
      height: 232 + (scale - 1) * 115,
      child: Stack(fit: StackFit.expand, children: [
        Image.asset('assets/images/home_header.jpg', fit: BoxFit.cover),
        const DecoratedBox(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0x77111411), Color(0x00111411)])),
        ),
        Positioned(
          left: 24,
          right: 20,
          top: 22,
          bottom: 19,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('走上',
                style: TextStyle(
                    fontFamily: 'GRemoteEditorial',
                    fontFamilyFallback: ['Noto Serif CJK SC'],
                    fontSize: 21,
                    letterSpacing: 5,
                    color: Color(0xFFF0EEE7))),
            const Padding(
              padding: EdgeInsets.only(left: 19, top: 5),
              child: Text('街头',
                  style: TextStyle(
                      fontFamily: 'GRemoteEditorial',
                      fontFamilyFallback: ['Noto Serif CJK SC'],
                      fontSize: 43,
                      height: 1.15,
                      letterSpacing: 4,
                      color: Color(0xFFF0EEE7))),
            ),
            const Spacer(),
            Container(width: 22, height: 1, color: const Color(0x99E1E0DA)),
            const SizedBox(height: 9),
            const Text('让平凡的日子，\n留下不平凡的眼光。',
                style: TextStyle(
                    fontSize: 11,
                    height: 1.8,
                    letterSpacing: .8,
                    color: Color(0xFFE1E0DA))),
          ]),
        ),
      ]),
    );
  }
}
