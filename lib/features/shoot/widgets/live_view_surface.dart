import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

class LiveViewSurface extends StatelessWidget {
  const LiveViewSurface({required this.frame, super.key});

  final Uint8List? frame;

  @override
  Widget build(BuildContext context) {
    final bytes = frame;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: GRemoteColors.divider),
      ),
      child: AspectRatio(
        aspectRatio: 6 / 5,
        child: Stack(fit: StackFit.expand, children: [
          if (bytes == null)
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.no_photography_outlined,
                    color: GRemoteColors.muted, size: 32),
                SizedBox(height: 14),
                Text('连接相机后显示取景画面',
                    style: TextStyle(
                        color: GRemoteColors.muted,
                        fontSize: 12,
                        letterSpacing: 1)),
              ],
            )
          else
            Image.memory(
              bytes,
              key: ValueKey(bytes),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            ),
          const Positioned(
              left: 0, top: 0, child: _ViewfinderCorner(top: true, left: true)),
          const Positioned(
              right: 0,
              top: 0,
              child: _ViewfinderCorner(top: true, left: false)),
          const Positioned(
              left: 0,
              bottom: 0,
              child: _ViewfinderCorner(top: false, left: true)),
          const Positioned(
              right: 0,
              bottom: 0,
              child: _ViewfinderCorner(top: false, left: false)),
        ]),
      ),
    );
  }
}

class _ViewfinderCorner extends StatelessWidget {
  const _ViewfinderCorner({required this.top, required this.left});

  final bool top;
  final bool left;

  @override
  Widget build(BuildContext context) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          border: Border(
            top: top
                ? const BorderSide(color: GRemoteColors.gold, width: 2)
                : BorderSide.none,
            bottom: top
                ? BorderSide.none
                : const BorderSide(color: GRemoteColors.gold, width: 2),
            left: left
                ? const BorderSide(color: GRemoteColors.gold, width: 2)
                : BorderSide.none,
            right: left
                ? BorderSide.none
                : const BorderSide(color: GRemoteColors.gold, width: 2),
          ),
        ),
      );
}
