import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

class ShootViewfinder extends StatelessWidget {
  const ShootViewfinder({
    required this.frame,
    required this.connected,
    required this.onConnect,
    this.overlay = const SizedBox.shrink(),
    super.key,
  });

  final Uint8List? frame;
  final bool connected;
  final VoidCallback onConnect;
  final Widget overlay;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          Center(
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: frame == null
                  ? const ColoredBox(
                      color: Color(0xFF080908),
                      child: Center(
                        child: Text('连接相机后显示取景画面',
                            style: TextStyle(
                                color: GRemoteColors.muted, fontSize: 12)),
                      ),
                    )
                  : Image.memory(frame!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.low),
            ),
          ),
          const Center(
            child: SizedBox(
              width: 34,
              height: 34,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(
                      BorderSide(color: Color(0x99FFFFFF), width: .7)),
                ),
              ),
            ),
          ),
          if (!connected)
            Positioned(
              right: 12,
              bottom: 12,
              child: TextButton(
                onPressed: onConnect,
                child: const Text('前往连接',
                    style: TextStyle(color: GRemoteColors.gold)),
              ),
            ),
          overlay,
        ]),
      );
}
