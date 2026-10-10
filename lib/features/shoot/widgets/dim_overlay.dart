import 'package:flutter/material.dart';

class DimOverlay extends StatelessWidget {
  const DimOverlay(
      {required this.progress, required this.onDismiss, super.key});

  final String progress;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: GestureDetector(
          onTap: onDismiss,
          child: ColoredBox(
            color: const Color(0xF2000000),
            child: Center(
              child: Text(progress,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          ),
        ),
      );
}
