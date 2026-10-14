import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../camera/program/program_runner.dart';
import 'shutter_button.dart';

class ShootBottomBar extends StatelessWidget {
  const ShootBottomBar({
    required this.connected,
    this.focusing = false,
    this.shutterHeld = false,
    required this.program,
    required this.onPressed,
    required this.onReleased,
    required this.onStop,
    required this.onPause,
    required this.onResume,
    required this.onLibrary,
    super.key,
  });

  final bool connected;
  final bool focusing;
  final bool shutterHeld;
  final ProgramRunState program;
  final Future<void> Function() onPressed;
  final Future<void> Function() onReleased;
  final VoidCallback onStop;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onLibrary;

  bool get _active =>
      program.phase == RunPhase.running || program.phase == RunPhase.paused;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 92,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          InkResponse(
            onTap: onLibrary,
            radius: 28,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: GRemoteColors.raised,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: GRemoteColors.divider),
              ),
              child: const Icon(Icons.photo_outlined,
                  size: 22, color: GRemoteColors.muted),
            ),
          ),
          if (_active)
            GestureDetector(
              key: const Key('shutter-button'),
              onTap: onStop,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: GRemoteColors.danger,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
            )
          else
            Transform.scale(
              scale: .82,
              child: ShutterButton(
                enabled: connected && !focusing,
                onPressed: onPressed,
                onReleased: onReleased,
              ),
            ),
          if (_active)
            IconButton.filledTonal(
              key: const Key('program-pause-button'),
              onPressed: !connected || focusing || shutterHeld
                  ? null
                  : program.phase == RunPhase.running
                      ? onPause
                      : onResume,
              tooltip: program.phase == RunPhase.running ? '暂停' : '继续',
              icon: Text(program.phase == RunPhase.running ? 'Ⅱ' : '▶',
                  style: const TextStyle(fontSize: 11)),
            )
          else
            const SizedBox(width: 48, height: 48),
        ]),
      );
}
