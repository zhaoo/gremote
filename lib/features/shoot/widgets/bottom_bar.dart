import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../camera/program/program_runner.dart';
import 'shutter_button.dart';
import '../../library/library_controller.dart';
import '../../../darkroom/darkroom_providers.dart';

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
    required this.onFocus,
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
  final VoidCallback onFocus;

  bool get _active =>
      program.phase == RunPhase.running || program.phase == RunPhase.paused;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 108,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          InkResponse(
            onTap: onLibrary,
            radius: 28,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: GRemoteColors.raised,
                shape: BoxShape.circle,
                border: Border.all(color: GRemoteColors.divider),
              ),
              child: ClipOval(child: Consumer(builder: (context, ref, _) {
                final id = ref.watch(libraryControllerProvider
                    .select((s) => s.items.firstOrNull?.id));
                final bytes = id == null
                    ? null
                    : ref.watch(thumbnailProvider(id)).valueOrNull;
                return bytes == null
                    ? const Icon(Icons.photo_outlined,
                        size: 22, color: GRemoteColors.muted)
                    : Image.memory(bytes,
                        fit: BoxFit.cover, gaplessPlayback: true);
              })),
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
            ShutterButton(
              enabled: connected && !focusing,
              onPressed: onPressed,
              onReleased: onReleased,
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
            SizedBox(
                width: 49,
                height: 49,
                child: OutlinedButton(
                  key: const Key('af-button'),
                  onPressed:
                      connected && !focusing && !shutterHeld ? onFocus : null,
                  style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                      side: const BorderSide(color: GRemoteColors.divider)),
                  child: const Text('AF',
                      semanticsLabel: '独立对焦', style: TextStyle(fontSize: 13)),
                )),
        ]),
      );
}
